package olcrtcclient

// Amnezia integration layer for olcRTC. olcRTC is consumed as a black box
// through its public mobile package: a cnc runtime that exposes a loopback
// SOCKS5 listener and carries the tunnel over WebRTC (pion). This layer starts
// that runtime, wires Android's VpnService.protect into it, and attaches a
// gVisor netstack (see netstack.go) to the VpnService TUN that feeds every
// flow into the SOCKS5 listener.
//
// Unlike the dnstt integration, no protocol code is vendored and no upstream
// patch is needed: olcRTC's mobile package already exports SetProtector, which
// forwards to its internal protect layer (ProtectedNet), covering pion ICE,
// provider HTTPS and WebSocket sockets on all engines.

import (
	"errors"
	"fmt"
	"log"
	"net"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	olcmobile "github.com/openlibrecommunity/olcrtc/mobile"
)

// Tunnel states reported to the Android layer.
const (
	StateConnected    = "connected"
	StateReconnecting = "reconnecting"
	StateDisconnected = "disconnected"
)

const (
	// dialTimeout bounds a single dial to the loopback SOCKS5 listener.
	dialTimeout = 15 * time.Second

	// readyTimeout bounds how long we wait for the runtime to bring the
	// SOCKS5 listener up before giving up on Start.
	readyTimeout = 45 * time.Second

	// stopTimeout bounds the runtime's graceful shutdown.
	stopTimeout = 5 * time.Second

	// downLogInterval throttles "tunnel is down" logging: applications retry
	// several times per second and one line per attempt buries the log.
	downLogInterval = 15 * time.Second
)

var (
	validProviders  = map[string]bool{"jitsi": true, "telemost": true, "wbstream": true, "none": true}
	validTransports = map[string]bool{"datachannel": true, "vp8channel": true, "seichannel": true, "videochannel": true}
	keyHexRe        = regexp.MustCompile(`^[0-9a-fA-F]{64}$`)
)

// errTunnelDown is returned by dialSocks while the runtime is not serving, so
// callers can fail fast and quietly instead of logging every attempt.
var errTunnelDown = errors.New("olcrtc: tunnel is down")

// ProtectFunc excludes a socket from the VPN routes. On Android it is backed by
// VpnService.protect. Returning false aborts the dial.
type ProtectFunc func(fd int) bool

// StateFunc reports tunnel state transitions to the host application.
type StateFunc func(state string)

// Config describes one olcRTC tunnel.
type Config struct {
	// TunFd is the VpnService TUN descriptor. The Client takes ownership and
	// closes it on Stop.
	TunFd int

	// TunMtu is the MTU the TUN interface was established with.
	TunMtu int

	// Provider selects the cover service: jitsi, telemost, wbstream or none.
	// The WebRTC engine is derived from it by olcRTC.
	Provider string

	// Transport selects how bytes are encoded onto the media session:
	// datachannel, vp8channel, seichannel or videochannel.
	Transport string

	// RoomURL is the provider room URL or id both peers share.
	RoomURL string

	// KeyHex is the 64-hex-digit (32-byte) shared tunnel key.
	KeyHex string

	// DNSServer, when set, is the resolver olcRTC uses for its own lookups
	// (reached outside the tunnel via the protected net).
	DNSServer string

	// ProviderToken is an optional pre-issued provider account token.
	ProviderToken string
}

// Client is a running olcRTC tunnel.
type Client struct {
	cfg     Config
	protect ProtectFunc
	onState StateFunc

	mu        sync.Mutex
	running   bool
	runtime   *olcmobile.Runtime
	netStack  *netStack
	socksAddr string

	// downMu guards the throttled "tunnel is down" logging.
	downMu      sync.Mutex
	lastDownLog time.Time
}

// protector adapts a ProtectFunc to olcRTC's mobile.SocketProtector.
type protector struct{ fn ProtectFunc }

func (p protector) Protect(fd int) bool {
	if p.fn == nil {
		return true
	}
	return p.fn(fd)
}

// NewClient validates cfg and returns a Client that has not been started yet.
// onState may be nil.
func NewClient(cfg Config, protect ProtectFunc, onState StateFunc) (*Client, error) {
	cfg.Provider = strings.ToLower(strings.TrimSpace(cfg.Provider))
	cfg.Transport = strings.ToLower(strings.TrimSpace(cfg.Transport))
	cfg.RoomURL = strings.TrimSpace(cfg.RoomURL)
	cfg.KeyHex = strings.TrimSpace(cfg.KeyHex)
	cfg.DNSServer = strings.TrimSpace(cfg.DNSServer)
	cfg.ProviderToken = strings.TrimSpace(cfg.ProviderToken)

	if !validProviders[cfg.Provider] {
		return nil, fmt.Errorf("olcrtc: invalid provider %q", cfg.Provider)
	}
	if !validTransports[cfg.Transport] {
		return nil, fmt.Errorf("olcrtc: invalid transport %q", cfg.Transport)
	}
	if !keyHexRe.MatchString(cfg.KeyHex) {
		return nil, errors.New("olcrtc: key must be 64 hex characters (32 bytes)")
	}
	if cfg.RoomURL == "" {
		return nil, errors.New("olcrtc: room URL is empty")
	}
	if cfg.TunMtu <= 0 {
		cfg.TunMtu = 1500
	}
	return &Client{cfg: cfg, protect: protect, onState: onState}, nil
}

// notifyState reports a state transition, if the host asked to be told.
func (c *Client) notifyState(state string) {
	if c.onState != nil {
		c.onState(state)
	}
}

// logTunnelDown logs at most one line per downLogInterval while the tunnel is
// unusable, so a dead session does not flood the log.
func (c *Client) logTunnelDown(context string, err error) {
	c.downMu.Lock()
	defer c.downMu.Unlock()
	if time.Since(c.lastDownLog) < downLogInterval {
		return
	}
	c.lastDownLog = time.Now()
	log.Printf("olcrtc: %s while the tunnel is down (%v); further such messages are suppressed for %s",
		context, err, downLogInterval)
}

// Start brings the olcRTC runtime up and attaches the network stack to the TUN.
func (c *Client) Start() error {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.running {
		return errors.New("olcrtc: client already running")
	}

	const socksHost = "127.0.0.1"
	port, err := pickLoopbackPort()
	if err != nil {
		return fmt.Errorf("olcrtc: reserving socks port: %w", err)
	}
	socksAddr := net.JoinHostPort(socksHost, strconv.Itoa(port))

	rt := olcmobile.New()
	rt.SetProvider(c.cfg.Provider)
	rt.SetTransport(c.cfg.Transport)
	rt.SetRoom(c.cfg.RoomURL)
	rt.SetKey(c.cfg.KeyHex)
	if c.cfg.DNSServer != "" {
		rt.SetDNS(c.cfg.DNSServer)
	}
	if c.cfg.ProviderToken != "" {
		rt.SetProviderToken(c.cfg.ProviderToken)
	}
	rt.SetSocksListenHost(socksHost)
	rt.SetSocksPort(port)
	// The protector is process-wide; set it before Start so the runtime's
	// first sockets (provider HTTPS, ICE) are already excluded from the TUN.
	rt.SetProtector(protector{c.protect})

	if err := rt.Start(); err != nil {
		rt.SetProtector(nil)
		return fmt.Errorf("olcrtc: starting runtime: %w", err)
	}
	if err := rt.WaitReady(int(readyTimeout / time.Millisecond)); err != nil {
		rt.Stop(int(stopTimeout / time.Millisecond))
		rt.SetProtector(nil)
		return fmt.Errorf("olcrtc: runtime not ready: %w", err)
	}

	ns, err := newNetStack(c.cfg.TunFd, c.cfg.TunMtu, c)
	if err != nil {
		rt.Stop(int(stopTimeout / time.Millisecond))
		rt.SetProtector(nil)
		return fmt.Errorf("olcrtc: attaching network stack to TUN: %w", err)
	}

	c.runtime = rt
	c.netStack = ns
	c.socksAddr = socksAddr
	c.running = true

	log.Printf("olcrtc: tunnel up (provider %s, transport %s, socks %s)",
		c.cfg.Provider, c.cfg.Transport, socksAddr)
	c.notifyState(StateConnected)
	return nil
}

// dialSocks opens a TCP connection to olcRTC's loopback SOCKS5 listener. This
// socket stays on the host loopback and is never routed through the TUN, so it
// is deliberately not protected.
func (c *Client) dialSocks() (net.Conn, error) {
	c.mu.Lock()
	addr := c.socksAddr
	running := c.running
	c.mu.Unlock()

	if !running || addr == "" {
		return nil, errTunnelDown
	}
	d := net.Dialer{Timeout: dialTimeout}
	return d.Dial("tcp", addr)
}

// isTunnelDown reports whether err means "runtime not serving yet" rather than
// a real per-connection failure, so callers can stay quiet.
func isTunnelDown(err error) bool {
	return errors.Is(err, errTunnelDown) || errors.Is(err, syscall.ECONNREFUSED)
}

// Stop tears the tunnel down. It is safe to call more than once.
func (c *Client) Stop() error {
	c.mu.Lock()
	defer c.mu.Unlock()

	if !c.running {
		if c.runtime != nil {
			c.runtime.Stop(int(stopTimeout / time.Millisecond))
			c.runtime.SetProtector(nil)
			c.runtime = nil
		}
		return nil
	}
	c.running = false

	if c.netStack != nil {
		c.netStack.Close()
		c.netStack = nil
	}
	if c.runtime != nil {
		if err := c.runtime.Stop(int(stopTimeout / time.Millisecond)); err != nil {
			log.Printf("olcrtc: runtime stop: %v", err)
		}
		c.runtime.SetProtector(nil)
		c.runtime = nil
	}
	c.socksAddr = ""

	log.Printf("olcrtc: tunnel stopped")
	c.notifyState(StateDisconnected)
	return nil
}

// pickLoopbackPort reserves a free loopback TCP port for olcRTC's SOCKS5
// listener. There is a small window between closing the probe listener and the
// runtime binding it; on a dedicated VPN process this is not a practical
// concern.
func pickLoopbackPort() (int, error) {
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return 0, err
	}
	defer l.Close()
	return l.Addr().(*net.TCPAddr).Port, nil
}
