# Go TCP Socket Client for Payment Host

A production-ready ISO 8583 TCP socket client with length-prefix framing, deadline-based I/O, exponential backoff reconnect, and auto-reversal on timeout.

## Package Structure

```
pkg/gateway/
  client.go         -- TCPClient: connect, send, receive
  framing.go        -- 2-byte length prefix encode/decode
  reversal.go       -- auto-reversal trigger
  backoff.go        -- exponential backoff with jitter
  client_test.go    -- table-driven tests
```

## client.go

```go
package gateway

import (
    "context"
    "encoding/binary"
    "fmt"
    "io"
    "net"
    "sync"
    "time"
)

const (
    defaultReadTimeout  = 30 * time.Second
    defaultWriteTimeout = 10 * time.Second
    maxMessageSize      = 64 * 1024 // 64 KB
)

// TCPClient manages a persistent TCP connection to a payment host.
// It handles ISO 8583 2-byte length-prefix framing, deadlines, and reconnection.
type TCPClient struct {
    addr          string
    readTimeout   time.Duration
    writeTimeout  time.Duration
    reversalFn    ReversalFunc

    mu   sync.Mutex
    conn net.Conn
}

// ReversalFunc is called when a send succeeds but no response is received within the read deadline.
// Implementations must send a 0400 reversal for the original message.
type ReversalFunc func(ctx context.Context, originalMsg []byte) error

// NewTCPClient creates a new payment host TCP client.
func NewTCPClient(addr string, reversalFn ReversalFunc) *TCPClient {
    return &TCPClient{
        addr:         addr,
        readTimeout:  defaultReadTimeout,
        writeTimeout: defaultWriteTimeout,
        reversalFn:   reversalFn,
    }
}

// Send sends an ISO 8583 message and returns the response.
// If the connection is not established, it connects first.
// If a response is not received within the read deadline, it triggers a reversal.
func (c *TCPClient) Send(ctx context.Context, msg []byte) ([]byte, error) {
    c.mu.Lock()
    defer c.mu.Unlock()

    conn, err := c.ensureConnected(ctx)
    if err != nil {
        return nil, fmt.Errorf("gateway.Send connect: %w", err)
    }

    // Write with deadline
    if err := conn.SetWriteDeadline(time.Now().Add(c.writeTimeout)); err != nil {
        return nil, fmt.Errorf("gateway.Send set write deadline: %w", err)
    }

    if err := writeFrame(conn, msg); err != nil {
        // Write failed — connection is suspect, close it
        _ = conn.Close()
        c.conn = nil
        return nil, fmt.Errorf("gateway.Send write: %w", err)
    }

    // Read with deadline — critical: write succeeded, so reversal must fire on timeout
    if err := conn.SetReadDeadline(time.Now().Add(c.readTimeout)); err != nil {
        // Could not set deadline — trigger reversal, treat as timeout
        _ = c.triggerReversal(ctx, msg)
        return nil, fmt.Errorf("gateway.Send set read deadline: %w", err)
    }

    resp, err := readFrame(conn)
    if err != nil {
        var netErr net.Error
        if isNetError(err, &netErr) && netErr.Timeout() {
            // TIMEOUT after successful write: unknown outcome — must reverse
            _ = conn.Close()
            c.conn = nil
            reversalErr := c.triggerReversal(ctx, msg)
            if reversalErr != nil {
                return nil, fmt.Errorf("gateway.Send timeout and reversal failed: write ok, read timeout: %w", reversalErr)
            }
            return nil, fmt.Errorf("gateway.Send timeout: reversal sent: %w", err)
        }
        _ = conn.Close()
        c.conn = nil
        return nil, fmt.Errorf("gateway.Send read: %w", err)
    }

    return resp, nil
}

func (c *TCPClient) ensureConnected(ctx context.Context) (net.Conn, error) {
    if c.conn != nil {
        return c.conn, nil
    }
    conn, err := connectWithBackoff(ctx, c.addr)
    if err != nil {
        return nil, err
    }
    c.conn = conn
    return conn, nil
}

func (c *TCPClient) triggerReversal(ctx context.Context, originalMsg []byte) error {
    if c.reversalFn == nil {
        return nil
    }
    // Reversal must be sent on a NEW connection — original is closed
    return c.reversalFn(ctx, originalMsg)
}

// Close closes the underlying TCP connection.
func (c *TCPClient) Close() error {
    c.mu.Lock()
    defer c.mu.Unlock()
    if c.conn != nil {
        err := c.conn.Close()
        c.conn = nil
        return err
    }
    return nil
}
```

## framing.go

```go
package gateway

import (
    "encoding/binary"
    "fmt"
    "io"
    "net"
)

// writeFrame writes msg prefixed with a 2-byte big-endian length to w.
// This is the standard ISO 8583 TCP framing used by most acquirer hosts.
func writeFrame(w io.Writer, msg []byte) error {
    if len(msg) > maxMessageSize {
        return fmt.Errorf("message too large: %d bytes (max %d)", len(msg), maxMessageSize)
    }

    header := make([]byte, 2)
    binary.BigEndian.PutUint16(header, uint16(len(msg)))

    // Write header + body as single syscall where possible
    buf := make([]byte, 2+len(msg))
    copy(buf[:2], header)
    copy(buf[2:], msg)

    _, err := w.Write(buf)
    return err
}

// readFrame reads a 2-byte length-prefixed message from r.
func readFrame(r io.Reader) ([]byte, error) {
    header := make([]byte, 2)
    if _, err := io.ReadFull(r, header); err != nil {
        return nil, fmt.Errorf("read frame header: %w", err)
    }

    length := binary.BigEndian.Uint16(header)
    if length == 0 {
        return nil, fmt.Errorf("received zero-length frame")
    }
    if int(length) > maxMessageSize {
        return nil, fmt.Errorf("frame length %d exceeds maximum %d", length, maxMessageSize)
    }

    body := make([]byte, length)
    if _, err := io.ReadFull(r, body); err != nil {
        return nil, fmt.Errorf("read frame body (expected %d bytes): %w", length, err)
    }

    return body, nil
}

func isNetError(err error, target *net.Error) bool {
    if err == nil {
        return false
    }
    var netErr net.Error
    if ok := errors.As(err, &netErr); ok {
        *target = netErr
        return true
    }
    return false
}
```

## backoff.go — Reconnect with Exponential Backoff

```go
package gateway

import (
    "context"
    "fmt"
    "math/rand"
    "net"
    "time"
)

const (
    initialBackoff = 500 * time.Millisecond
    maxBackoff     = 30 * time.Second
    maxAttempts    = 5
    dialTimeout    = 10 * time.Second
)

// connectWithBackoff attempts to establish a TCP connection, retrying with
// exponential backoff + jitter on transient failures.
func connectWithBackoff(ctx context.Context, addr string) (net.Conn, error) {
    backoff := initialBackoff

    for attempt := 1; attempt <= maxAttempts; attempt++ {
        dialer := net.Dialer{Timeout: dialTimeout}
        conn, err := dialer.DialContext(ctx, "tcp", addr)
        if err == nil {
            return conn, nil
        }

        // Context cancelled — stop immediately
        if ctx.Err() != nil {
            return nil, fmt.Errorf("connect aborted: %w", ctx.Err())
        }

        if attempt == maxAttempts {
            return nil, fmt.Errorf("gateway unreachable after %d attempts: %w", maxAttempts, err)
        }

        // Jitter: backoff ± 20%
        jitter := time.Duration(rand.Int63n(int64(backoff / 5)))
        sleep := backoff + jitter - (backoff / 10)

        select {
        case <-ctx.Done():
            return nil, fmt.Errorf("connect aborted during backoff: %w", ctx.Err())
        case <-time.After(sleep):
        }

        backoff = min(backoff*2, maxBackoff)
    }

    return nil, fmt.Errorf("connect failed: max attempts reached")
}
```

## reversal.go — Auto-Reversal Trigger

```go
package gateway

import (
    "context"
    "fmt"
)

// ReversalSender sends a 0400 reversal for a timed-out 0200 request.
// It uses a separate TCPClient instance to ensure the reversal goes out
// on a clean connection even if the original connection was broken.
type ReversalSender struct {
    client    *TCPClient
    builder   ReversalBuilder
}

// ReversalBuilder constructs a 0400 reversal message from an original 0200 message.
type ReversalBuilder interface {
    BuildReversal(original []byte) ([]byte, error)
}

func NewReversalSender(addr string, builder ReversalBuilder) *ReversalSender {
    // Reversal sender has no reversalFn — reversals are never reversed
    client := NewTCPClient(addr, nil)
    return &ReversalSender{client: client, builder: builder}
}

// Send constructs and sends a 0400 reversal for the given original message.
// It retries up to 3 times with backoff — reversals must be delivered.
func (r *ReversalSender) Send(ctx context.Context, originalMsg []byte) error {
    reversal, err := r.builder.BuildReversal(originalMsg)
    if err != nil {
        return fmt.Errorf("reversal.Send build: %w", err)
    }

    for attempt := 1; attempt <= 3; attempt++ {
        resp, err := r.client.Send(ctx, reversal)
        if err != nil {
            if attempt == 3 {
                return fmt.Errorf("reversal.Send failed after 3 attempts: %w", err)
            }
            continue
        }

        mti := string(resp[:4])
        if mti != "0410" && mti != "0430" {
            return fmt.Errorf("reversal.Send unexpected response MTI: %s", mti)
        }

        return nil
    }
    return fmt.Errorf("reversal.Send: exhausted retries")
}
```

## Usage Example

```go
// main.go / wire-up
reversalBuilder := &ISO8583ReversalBuilder{stan: stanGenerator}
reversalSender  := gateway.NewReversalSender(cfg.GatewayAddr, reversalBuilder)

client := gateway.NewTCPClient(cfg.GatewayAddr, reversalSender.Send)
defer client.Close()

// In payment handler:
ctx, cancel := context.WithTimeout(r.Context(), 35*time.Second)
defer cancel()

resp, err := client.Send(ctx, iso8583Bytes)
if err != nil {
    // If "reversal sent" in error — reversal is in flight
    // Mark transaction as "reversal_pending" not "failed"
    if strings.Contains(err.Error(), "reversal sent") {
        transaction.Status = "reversal_pending"
    }
    return nil, fmt.Errorf("payment host: %w", err)
}
```
