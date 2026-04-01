---
name: go-patterns
description: Go patterns for payment microservices — TCP socket clients with context and reconnect, ISO 8583 message builder, connection pooling, graceful shutdown, structured logging with slog, Prometheus metrics, and gRPC unary RPC with timeout mapping.
origin: fintech-stack
---

# Go Patterns

Go payment services communicate over persistent TCP connections to payment hosts, handle ISO 8583 binary framing, and must shut down cleanly without dropping in-flight transactions. These patterns cover the full stack from socket client to metrics export.

## When to Activate

- Writing a payment host connector (TCP socket client)
- Implementing ISO 8583 message handling
- Designing a connection pool for persistent host connections
- Adding structured logging, Prometheus metrics, or gRPC
- Developer asks "how do I handle graceful shutdown?" or "connection pool in Go"

---

## TCP Socket Client with Context, Deadlines, and Reconnect

```go
// internal/host/client.go
package host

import (
    "context"
    "fmt"
    "log/slog"
    "net"
    "time"
)

type Client struct {
    addr    string
    timeout time.Duration
    logger  *slog.Logger
    conn    net.Conn
}

func NewClient(addr string, timeout time.Duration, logger *slog.Logger) *Client {
    return &Client{addr: addr, timeout: timeout, logger: logger}
}

func (c *Client) Send(ctx context.Context, msg []byte) ([]byte, error) {
    conn, err := c.getConn(ctx)
    if err != nil {
        return nil, fmt.Errorf("get connection: %w", err)
    }

    deadline, ok := ctx.Deadline()
    if !ok {
        deadline = time.Now().Add(c.timeout)
    }
    conn.SetDeadline(deadline)

    if _, err := conn.Write(msg); err != nil {
        c.conn = nil // force reconnect on next call
        return nil, fmt.Errorf("write: %w", err)
    }

    buf := make([]byte, 4096)
    n, err := conn.Read(buf)
    if err != nil {
        c.conn = nil
        return nil, fmt.Errorf("read: %w", err)
    }

    return buf[:n], nil
}

func (c *Client) getConn(ctx context.Context) (net.Conn, error) {
    if c.conn != nil {
        return c.conn, nil
    }
    var d net.Dialer
    conn, err := d.DialContext(ctx, "tcp", c.addr)
    if err != nil {
        return nil, fmt.Errorf("dial %s: %w", c.addr, err)
    }
    c.conn = conn
    c.logger.Info("connected to payment host", "addr", c.addr)
    return conn, nil
}
```

---

## ISO 8583 Message Builder

```go
// internal/iso8583/message.go
package iso8583

import (
    "encoding/binary"
    "encoding/hex"
    "fmt"
)

type Message struct {
    MTI    string
    Fields map[int]string
}

func NewMessage(mti string) *Message {
    return &Message{MTI: mti, Fields: make(map[int]string)}
}

func (m *Message) Set(fieldNum int, value string) *Message {
    m.Fields[fieldNum] = value
    return m
}

func (m *Message) Get(fieldNum int) string {
    return m.Fields[fieldNum]
}

// Build serialises the ISO 8583 message to bytes
func (m *Message) Build() ([]byte, error) {
    // MTI (4 bytes BCD)
    mtiBytes, err := hex.DecodeString(m.MTI)
    if err != nil {
        return nil, fmt.Errorf("invalid MTI %q: %w", m.MTI, err)
    }

    // Primary bitmap (8 bytes)
    bitmap := [8]byte{}
    for fieldNum := range m.Fields {
        if fieldNum >= 1 && fieldNum <= 64 {
            byteIdx := (fieldNum - 1) / 8
            bitIdx := 7 - ((fieldNum - 1) % 8)
            bitmap[byteIdx] |= 1 << bitIdx
        }
    }

    var buf []byte
    buf = append(buf, mtiBytes...)
    buf = append(buf, bitmap[:]...)

    // Field data (simplified — real implementation handles LL/LLL VAR fields)
    for i := 1; i <= 64; i++ {
        if val, ok := m.Fields[i]; ok {
            buf = append(buf, []byte(val)...)
        }
    }

    // Prepend 2-byte length header
    length := make([]byte, 2)
    binary.BigEndian.PutUint16(length, uint16(len(buf)))
    return append(length, buf...), nil
}
```

---

## Connection Pool for Payment Host

```go
// internal/host/pool.go
package host

import (
    "context"
    "net"
    "time"
)

type Pool struct {
    addr    string
    conns   chan net.Conn
    maxSize int
    timeout time.Duration
}

func NewPool(addr string, maxSize int, timeout time.Duration) *Pool {
    return &Pool{
        addr:    addr,
        conns:   make(chan net.Conn, maxSize),
        maxSize: maxSize,
        timeout: timeout,
    }
}

func (p *Pool) Get(ctx context.Context) (net.Conn, error) {
    select {
    case conn := <-p.conns:
        return conn, nil
    default:
        return net.DialTimeout("tcp", p.addr, p.timeout)
    }
}

func (p *Pool) Put(conn net.Conn) {
    select {
    case p.conns <- conn:
    default:
        conn.Close() // pool full — discard
    }
}
```

---

## Graceful Shutdown with Signal Handling

```go
// cmd/payment-service/main.go
package main

import (
    "context"
    "log/slog"
    "net/http"
    "os"
    "os/signal"
    "syscall"
    "time"
)

func main() {
    logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))

    srv := &http.Server{
        Addr:    ":8080",
        Handler: buildRouter(),
    }

    go func() {
        logger.Info("starting server", "addr", srv.Addr)
        if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
            logger.Error("server error", "error", err)
            os.Exit(1)
        }
    }()

    quit := make(chan os.Signal, 1)
    signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
    sig := <-quit
    logger.Info("shutdown signal received", "signal", sig)

    // Give in-flight requests 30s to complete
    ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
    defer cancel()

    if err := srv.Shutdown(ctx); err != nil {
        logger.Error("forced shutdown", "error", err)
    }
    logger.Info("server stopped cleanly")
}
```

---

## Structured Logging with slog

```go
// Use slog with JSON output for production
logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
    Level: slog.LevelInfo,
}))

// Add payment context to every log entry
logger.Info("payment authorised",
    slog.String("transaction_id", txn.ID),
    slog.String("merchant_id",    txn.MerchantID),
    slog.Int("amount",            txn.Amount),
    slog.String("currency",       txn.Currency),
    slog.String("response_code",  resp.ResponseCode),
    // Never log: full PAN, CVV, track data
)
```

---

## Prometheus Metrics

```go
// internal/metrics/payment.go
package metrics

import "github.com/prometheus/client_golang/prometheus"

var (
    PaymentTotal = prometheus.NewCounterVec(
        prometheus.CounterOpts{
            Name: "payment_requests_total",
            Help: "Total payment requests by status",
        },
        []string{"merchant_id", "status", "response_code"},
    )

    PaymentDuration = prometheus.NewHistogramVec(
        prometheus.HistogramOpts{
            Name:    "payment_duration_seconds",
            Help:    "Payment processing duration",
            Buckets: prometheus.DefBuckets,
        },
        []string{"merchant_id"},
    )
)

func init() {
    prometheus.MustRegister(PaymentTotal, PaymentDuration)
}
```

---

## gRPC Unary RPC with Timeout

```go
// Unary RPC with timeout and error mapping
func (s *PaymentServer) Authorise(ctx context.Context, req *pb.AuthRequest) (*pb.AuthResponse, error) {
    ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
    defer cancel()

    result, err := s.svc.Process(ctx, toDomain(req))
    if err != nil {
        return nil, status.Errorf(codes.Internal, "process payment: %v", err)
    }

    return toProto(result), nil
}
```

---

## Best Practices

- **`context` as first parameter on all I/O functions** — deadline propagation is how you avoid host timeouts leaving transactions in unknown state
- **Nil `c.conn` on write error** — forces reconnect on the next call rather than retrying on a broken connection
- **`fmt.Errorf("context: %w", err)`** — wrap errors at every layer so the call site appears in the error chain
- **`slog.NewJSONHandler`** — structured JSON logs are parseable by Datadog/CloudWatch; never use `fmt.Printf` for payment events
- **Prometheus counter at result point** — increment `payment_requests_total` with `status` and `response_code` labels after every host response
- **30s graceful shutdown window** — matches the maximum host timeout; in-flight payments get a full window to complete before SIGKILL
