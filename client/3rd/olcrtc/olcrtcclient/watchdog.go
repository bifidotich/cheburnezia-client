package olcrtcclient

// Tunnel liveness watchdog.
//
// olcRTC rebuilds a dropped WebRTC session by itself, but it gives up after a
// few handshake attempts and then keeps the SOCKS5 listener up with no session
// behind it, and a runtime that exits on a fatal error just stops. The mobile
// package reports neither: Runtime.State() stays "running" for the first case
// and nothing calls back for the second. Without a check the UI keeps saying
// "connected" while every connection hangs and fails.
//
// The watchdog judges liveness end to end. Any SOCKS5 CONNECT that the server
// acknowledged proves the session works, so while applications are using the
// tunnel their own connections are the signal and nothing extra is sent. When
// the tunnel is idle it opens one probe connection through it. A dead session
// first shows up as "reconnecting" (olcRTC may still recover on its own), and
// if it stays dead the runtime is restarted from scratch with backoff. The TUN
// and the network stack are kept across restarts.

import (
	"context"
	"errors"
	"log"
	"net"
	"time"
)

const (
	// probeInterval is how often liveness is evaluated.
	probeInterval = 15 * time.Second

	// probeTimeout bounds one probe. olcRTC holds a CONNECT for up to 60 s
	// while it waits for a session, so a dead session shows up as a timeout.
	probeTimeout = 30 * time.Second

	// failuresBeforeReconnecting is how many failed checks in a row turn the
	// state to "reconnecting".
	failuresBeforeReconnecting = 2

	// restartAfter is how long the session may stay dead before the runtime
	// is restarted. It leaves room for olcRTC's own reconnect, which needs
	// about 40 s to notice missed pongs and then several handshake attempts.
	restartAfter = 90 * time.Second

	// Bounds of the delay between runtime restarts that bring nothing back.
	restartBackoffMin = 60 * time.Second
	restartBackoffMax = 5 * time.Minute

	// runtimeStateRunning is mobile.Runtime.State() of a live generation.
	runtimeStateRunning = "running"
)

// probeTargets are reached from the olcRTC server, not from the phone. A
// connection there only has to be acknowledged by the server; the second
// target covers the first being unreachable from the exit node.
var probeTargets = []struct {
	ip   net.IP
	port uint16
}{
	{net.IPv4(1, 1, 1, 1), 53},
	{net.IPv4(8, 8, 8, 8), 53},
}

type health int

const (
	healthy health = iota
	// sessionDead: the runtime runs, but no session carries traffic.
	sessionDead
	// runtimeDead: the runtime has exited and will not recover by itself.
	runtimeDead
)

// markAlive records that the tunnel just carried a connection end to end.
func (c *Client) markAlive() {
	c.lastAlive.Store(time.Now().UnixNano())
}

// RequestRestart asks the watchdog to restart the runtime now, for example
// after the device switched networks and the WebRTC sockets are bound to the
// old one. It does not block.
func (c *Client) RequestRestart() {
	select {
	case c.restartReq <- struct{}{}:
	default:
	}
}

// setState reports state if it differs from the last reported one.
func (c *Client) setState(state string) {
	c.stateMu.Lock()
	if c.state == state {
		c.stateMu.Unlock()
		return
	}
	c.state = state
	c.stateMu.Unlock()
	log.Printf("olcrtc: tunnel %s", state)
	c.notifyState(state)
}

func (c *Client) watch(ctx context.Context, done chan<- struct{}) {
	defer close(done)

	ticker := time.NewTicker(probeInterval)
	defer ticker.Stop()

	var (
		failures       int
		deadSince      time.Time
		nextRestart    time.Time
		restartBackoff = restartBackoffMin
	)

	for {
		select {
		case <-ctx.Done():
			return
		case <-c.restartReq:
			c.setState(StateReconnecting)
			c.restartRuntime(ctx, "network changed")
			ticker.Reset(probeInterval)
		case <-ticker.C:
		}

		h := c.checkHealth(ctx)
		if ctx.Err() != nil {
			return
		}
		now := time.Now()

		if h == healthy {
			failures = 0
			deadSince = time.Time{}
			nextRestart = time.Time{}
			restartBackoff = restartBackoffMin
			c.setState(StateConnected)
			continue
		}

		failures++
		if deadSince.IsZero() {
			deadSince = now
		}
		if failures >= failuresBeforeReconnecting || h == runtimeDead {
			c.setState(StateReconnecting)
		}

		// An exited runtime has nothing left to wait for.
		due := h == runtimeDead || now.Sub(deadSince) >= restartAfter
		if due && !now.Before(nextRestart) {
			reason := "session dead for " + now.Sub(deadSince).Round(time.Second).String()
			if h == runtimeDead {
				reason = "runtime exited"
			}
			c.restartRuntime(ctx, reason)
			nextRestart = time.Now().Add(restartBackoff)
			restartBackoff = min(2*restartBackoff, restartBackoffMax)
			ticker.Reset(probeInterval)
		}
	}
}

// checkHealth reports whether the tunnel currently carries traffic.
func (c *Client) checkHealth(ctx context.Context) health {
	c.mu.Lock()
	rt := c.runtime
	c.mu.Unlock()

	if rt == nil || rt.State() != runtimeStateRunning {
		return runtimeDead
	}

	// Applications got a connection through recently: no probe needed.
	if last := c.lastAlive.Load(); last != 0 && time.Since(time.Unix(0, last)) < probeInterval {
		return healthy
	}

	for _, target := range probeTargets {
		err := c.probe(ctx, target.ip, target.port)
		if err == nil {
			c.markAlive()
			return healthy
		}
		if ctx.Err() != nil {
			return sessionDead
		}
		// Only a quick refusal from the server is worth a second target;
		// a timeout means the session itself is gone.
		var replyErr *socksReplyError
		if !errors.As(err, &replyErr) {
			log.Printf("olcrtc: liveness probe failed: %v", err)
			return sessionDead
		}
		log.Printf("olcrtc: liveness probe to %s refused: %v", target.ip, err)
	}
	return sessionDead
}

// probe opens one CONNECT through the tunnel and closes it.
func (c *Client) probe(ctx context.Context, ip net.IP, port uint16) error {
	conn, err := c.dialSocks()
	if err != nil {
		return err
	}
	defer conn.Close()

	stop := context.AfterFunc(ctx, func() { conn.Close() })
	defer stop()

	if err := conn.SetDeadline(time.Now().Add(probeTimeout)); err != nil {
		return err
	}
	return socks5Connect(conn, ip, port)
}

// restartRuntime replaces the olcRTC runtime with a fresh one. The network
// stack keeps running: while no runtime is installed dialSocks reports the
// tunnel as down and connections are dropped quietly.
func (c *Client) restartRuntime(ctx context.Context, reason string) {
	log.Printf("olcrtc: restarting runtime (%s)", reason)

	c.mu.Lock()
	old := c.runtime
	c.runtime = nil
	c.socksAddr = ""
	c.mu.Unlock()

	// The protector is process-wide and the next runtime needs it too, so
	// it is not cleared here.
	if old != nil {
		if err := old.Stop(int(stopTimeout / time.Millisecond)); err != nil {
			log.Printf("olcrtc: stopping old runtime: %v", err)
		}
	}

	rt, addr, err := c.startRuntime(ctx)
	if err != nil {
		log.Printf("olcrtc: runtime restart failed: %v", err)
		return
	}

	c.mu.Lock()
	c.runtime = rt
	c.socksAddr = addr
	c.mu.Unlock()
	log.Printf("olcrtc: runtime restarted (socks %s)", addr)
}
