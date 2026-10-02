package olcrtcclient

import (
	"context"
	"errors"
	"io"
	"net"
	"testing"
	"time"
)

// fakeSocks serves the loopback side of olcRTC's SOCKS5 listener: it accepts
// the greeting and request and then answers with reply, or never answers when
// reply is negative, like olcRTC waiting for a session that does not come.
func fakeSocks(t *testing.T, reply int) string {
	t.Helper()
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { l.Close() })
	go func() {
		for {
			conn, err := l.Accept()
			if err != nil {
				return
			}
			go func() {
				defer conn.Close()
				greeting := make([]byte, 3)
				request := make([]byte, 10) // IPv4 CONNECT
				if _, err := io.ReadFull(conn, greeting); err != nil {
					return
				}
				conn.Write([]byte{socks5Version, socksAuthNone})
				if _, err := io.ReadFull(conn, request); err != nil {
					return
				}
				if reply < 0 {
					io.Copy(io.Discard, conn)
					return
				}
				conn.Write([]byte{socks5Version, byte(reply), 0, socksAtypIPv4, 0, 0, 0, 0, 0, 0})
			}()
		}
	}()
	return l.Addr().String()
}

func runningClient(addr string) *Client {
	return &Client{running: true, socksAddr: addr, restartReq: make(chan struct{}, 1)}
}

func TestProbeSucceeds(t *testing.T) {
	c := runningClient(fakeSocks(t, 0x00))
	if err := c.probe(context.Background(), net.IPv4(1, 1, 1, 1), 53); err != nil {
		t.Fatalf("probe: %v", err)
	}
}

func TestProbeReportsServerRefusal(t *testing.T) {
	c := runningClient(fakeSocks(t, 0x04))
	err := c.probe(context.Background(), net.IPv4(1, 1, 1, 1), 53)
	var replyErr *socksReplyError
	if !errors.As(err, &replyErr) || replyErr.code != 0x04 {
		t.Fatalf("probe error = %v, want a host unreachable reply", err)
	}
}

func TestProbeEndsWithContext(t *testing.T) {
	c := runningClient(fakeSocks(t, -1))
	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()

	start := time.Now()
	err := c.probe(ctx, net.IPv4(1, 1, 1, 1), 53)
	if err == nil {
		t.Fatal("probe of a silent proxy succeeded")
	}
	var replyErr *socksReplyError
	if errors.As(err, &replyErr) {
		t.Fatalf("silent proxy reported as a reply: %v", err)
	}
	if elapsed := time.Since(start); elapsed > 5*time.Second {
		t.Fatalf("probe ignored the context for %s", elapsed)
	}
}

func TestProbeWhileRuntimeIsSwapped(t *testing.T) {
	c := runningClient("")
	err := c.probe(context.Background(), net.IPv4(1, 1, 1, 1), 53)
	if !isTunnelDown(err) {
		t.Fatalf("probe error = %v, want tunnel down", err)
	}
}

func TestSetStateReportsChangesOnly(t *testing.T) {
	var got []string
	c := &Client{onState: func(s string) { got = append(got, s) }}
	for _, s := range []string{StateConnected, StateConnected, StateReconnecting, StateReconnecting, StateConnected} {
		c.setState(s)
	}
	want := []string{StateConnected, StateReconnecting, StateConnected}
	if len(got) != len(want) {
		t.Fatalf("reported %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("reported %v, want %v", got, want)
		}
	}
}
