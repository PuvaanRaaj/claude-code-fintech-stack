---
name: rate-limiting
description: Rate limiting patterns for payment APIs — Redis sliding window counter, per-merchant and per-IP limits, Laravel middleware implementation, Go middleware with atomic counters, burst allowance, and 429 response format with Retry-After header.
origin: fintech-stack
---

# Rate Limiting Patterns

Payment APIs are high-value targets for credential stuffing, enumeration attacks, and runaway retry loops from misconfigured clients. Rate limiting is the first line of defence — it protects your infrastructure, your downstream hosts (acquirers have their own rate limits), and your merchant clients from their own bugs.

## When to Activate

- Adding rate limiting to a payment submission or card verification endpoint
- Implementing per-merchant and per-IP limits with different thresholds
- Building a sliding window counter in Redis
- Writing a 429 response with correct `Retry-After` and `X-RateLimit-*` headers
- Configuring burst allowance for endpoints with legitimately bursty traffic (batch payments)
- Diagnosing a Redis TTL strategy that leaves stale keys accumulating in memory

---

## Sliding Window Algorithm

A fixed window counter (reset every 60 seconds) allows a burst of requests at the window boundary. A sliding window scores each request against a rolling time range, eliminating the boundary spike.

```
Sliding window using Redis sorted set:

ZADD  rate:{merchant_id}  {now_ms}  {uuid}   — add this request at current timestamp
ZCOUNT rate:{merchant_id}  {now_ms - 60000}  {now_ms}  — count requests in last 60s
ZREMRANGEBYSCORE rate:{merchant_id}  0  {now_ms - 60000} — prune expired entries
EXPIRE rate:{merchant_id}  120  — auto-expire the key if idle for 2 windows
```

The key insight: `ZCOUNT` over a time range gives an exact request count for any sliding window, not a stale bucket count.

---

## PHP/Laravel — Per-Merchant and Per-IP Middleware

```php
<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Redis;
use Symfony\Component\HttpFoundation\Response;

final class PaymentRateLimit
{
    // Limits per window (requests per 60 seconds)
    private const MERCHANT_LIMIT         = 100;
    private const IP_LIMIT               = 20;
    private const PAYMENT_SUBMIT_LIMIT   = 50;  // Tighter limit for /payments endpoint
    private const STATUS_CHECK_LIMIT     = 300; // Looser limit for /payments/{id}
    private const WINDOW_SECONDS         = 60;

    public function handle(Request $request, Closure $next): Response
    {
        $merchantId = $request->header('X-Merchant-ID');
        $ip         = $request->ip();
        $nowMs      = (int) (microtime(true) * 1000);
        $windowMs   = self::WINDOW_SECONDS * 1000;
        $limit      = $this->limitForEndpoint($request);

        // Per-merchant check
        if ($merchantId) {
            $merchantCount = $this->slidingCount("merchant:{$merchantId}", $nowMs, $windowMs);
            if ($merchantCount >= $limit) {
                return $this->tooManyRequests($limit, $merchantCount, self::WINDOW_SECONDS);
            }
        }

        // Per-IP check (lower threshold — catches unauthenticated probing)
        $ipCount = $this->slidingCount("ip:{$ip}", $nowMs, $windowMs);
        if ($ipCount >= self::IP_LIMIT) {
            return $this->tooManyRequests(self::IP_LIMIT, $ipCount, self::WINDOW_SECONDS);
        }

        $response = $next($request);

        // Attach rate limit headers on every response
        $remaining = max(0, $limit - ($merchantId ? $this->slidingCount("merchant:{$merchantId}", $nowMs, $windowMs) : $ipCount));
        $response->headers->set('X-RateLimit-Limit',     (string) $limit);
        $response->headers->set('X-RateLimit-Remaining', (string) $remaining);
        $response->headers->set('X-RateLimit-Reset',     (string) (time() + self::WINDOW_SECONDS));

        return $response;
    }

    private function slidingCount(string $key, int $nowMs, int $windowMs): int
    {
        $fullKey   = "ratelimit:{$key}";
        $requestId = uniqid('', true);

        Redis::pipeline(function ($pipe) use ($fullKey, $nowMs, $requestId, $windowMs) {
            $pipe->zadd($fullKey, $nowMs, $requestId);                        // Record request
            $pipe->zremrangebyscore($fullKey, 0, $nowMs - $windowMs);        // Prune old entries
            $pipe->expire($fullKey, (int) ($windowMs / 1000) * 2);          // Auto-expire key
        });

        return (int) Redis::zcount($fullKey, $nowMs - $windowMs, $nowMs);
    }

    private function limitForEndpoint(Request $request): int
    {
        if ($request->routeIs('payments.store')) {
            return self::PAYMENT_SUBMIT_LIMIT;
        }
        if ($request->routeIs('payments.show')) {
            return self::STATUS_CHECK_LIMIT;
        }
        return self::MERCHANT_LIMIT;
    }

    private function tooManyRequests(int $limit, int $current, int $windowSeconds): Response
    {
        $retryAfter = $windowSeconds; // Conservative — reset after full window

        return response()->json([
            'error'       => 'rate_limit_exceeded',
            'message'     => 'Too many requests. Please slow down.',
            'retry_after' => $retryAfter,
        ], 429, [
            'Retry-After'          => (string) $retryAfter,
            'X-RateLimit-Limit'    => (string) $limit,
            'X-RateLimit-Remaining'=> '0',
            'X-RateLimit-Reset'    => (string) (time() + $retryAfter),
        ]);
    }
}
```

Register in `bootstrap/app.php`:

```php
->withMiddleware(function (Middleware $middleware) {
    $middleware->prependToGroup('api', \App\Http\Middleware\PaymentRateLimit::class);
})
```

---

## Go — Middleware with Atomic Counters and Burst Allowance

```go
package middleware

import (
    "context"
    "fmt"
    "net/http"
    "strconv"
    "sync/atomic"
    "time"

    "github.com/redis/go-redis/v9"
)

type RateLimiter struct {
    redis       *redis.Client
    limit       int64
    burst       int64          // Extra requests allowed above limit in a burst
    windowSecs  int64
}

func NewRateLimiter(rdb *redis.Client, limit, burst int64, window time.Duration) *RateLimiter {
    return &RateLimiter{
        redis:      rdb,
        limit:      limit,
        burst:      burst,
        windowSecs: int64(window.Seconds()),
    }
}

func (rl *RateLimiter) Middleware(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        merchantID := r.Header.Get("X-Merchant-ID")
        key := fmt.Sprintf("ratelimit:merchant:%s", merchantID)

        count, err := rl.slidingCount(r.Context(), key)
        if err != nil {
            // Redis unavailable — fail open (allow the request) and log
            next.ServeHTTP(w, r)
            return
        }

        effectiveLimit := rl.limit + rl.burst
        remaining      := effectiveLimit - count
        if remaining < 0 {
            remaining = 0
        }

        w.Header().Set("X-RateLimit-Limit",     strconv.FormatInt(rl.limit, 10))
        w.Header().Set("X-RateLimit-Remaining", strconv.FormatInt(remaining, 10))
        w.Header().Set("X-RateLimit-Reset",     strconv.FormatInt(time.Now().Unix()+rl.windowSecs, 10))

        if count > effectiveLimit {
            w.Header().Set("Retry-After", strconv.FormatInt(rl.windowSecs, 10))
            w.WriteHeader(http.StatusTooManyRequests)
            _, _ = w.Write([]byte(`{"error":"rate_limit_exceeded","retry_after":` + strconv.FormatInt(rl.windowSecs, 10) + `}`))
            return
        }

        next.ServeHTTP(w, r)
    })
}

func (rl *RateLimiter) slidingCount(ctx context.Context, key string) (int64, error) {
    nowMs    := time.Now().UnixMilli()
    windowMs := rl.windowSecs * 1000
    member   := fmt.Sprintf("%d-%d", nowMs, nanoID())

    pipe := rl.redis.Pipeline()
    pipe.ZAdd(ctx, key, redis.Z{Score: float64(nowMs), Member: member})
    pipe.ZRemRangeByScore(ctx, key, "0", strconv.FormatInt(nowMs-windowMs, 10))
    pipe.Expire(ctx, key, time.Duration(rl.windowSecs*2)*time.Second)
    countCmd := pipe.ZCount(ctx, key, strconv.FormatInt(nowMs-windowMs, 10), strconv.FormatInt(nowMs, 10))

    if _, err := pipe.Exec(ctx); err != nil {
        return 0, err
    }

    return countCmd.Val(), nil
}

var nanoCounter atomic.Int64

func nanoID() int64 {
    return nanoCounter.Add(1)
}
```

---

## Rate Limit Headers

Every response from a rate-limited endpoint must carry these headers:

| Header | Value | Description |
|--------|-------|-------------|
| `X-RateLimit-Limit` | `100` | Maximum requests allowed in the window |
| `X-RateLimit-Remaining` | `47` | Requests remaining in the current window |
| `X-RateLimit-Reset` | `1714500060` | Unix timestamp when the window resets |
| `Retry-After` | `60` | Seconds to wait before retrying (only on 429) |

`Retry-After` on a 429 response must be an integer number of seconds per RFC 7231. Do not use an HTTP date format — many payment client SDKs parse it as an integer directly.

---

## Endpoint-Specific Limits

Different endpoints carry different risk profiles and traffic patterns:

| Endpoint | Limit | Rationale |
|----------|-------|-----------|
| `POST /payments` | 50 req/min per merchant | Payment submission — acquirer has its own rate limit downstream |
| `GET /payments/{id}` | 300 req/min per merchant | Status polling — bursty after payment submission |
| `POST /cards/verify` | 10 req/min per IP | Card verification — high-value enumeration target |
| `POST /refunds` | 20 req/min per merchant | Refund submission — lower volume by nature |
| `GET /health` | Unlimited | Health check — must not be rate limited |

---

## Redis Key TTL Strategy

```
Key pattern:    ratelimit:{scope}:{identifier}
Example:        ratelimit:merchant:mid_abc123
                ratelimit:ip:203.0.113.42

TTL:            2 × window_seconds
                e.g. 60s window → 120s TTL

Why 2×?        A key active at t=59 with a 60s window will still have
               entries from t=0 to t=59. At t=120, all those entries
               have aged out of every possible 60s window. Setting TTL
               to 1× window_seconds risks the key expiring while it
               still has valid entries for the current window.
```

`ZREMRANGEBYSCORE` prunes expired members on every request, so the sorted set never grows unboundedly. The `EXPIRE` call resets the TTL on every access — a key for an active merchant never expires mid-session.

---

## Best Practices

- **Fail open when Redis is unavailable** — a Redis outage should not block payments; log the failure at ERROR level, skip the rate limit check, and alert the on-call engineer
- **Use pipeline for ZADD + ZREMRANGEBYSCORE + EXPIRE** — these three commands must execute atomically to avoid a race where a slow request reads a count that includes just-pruned entries; a Lua script is an alternative for strict atomicity
- **Set per-IP limits lower than per-merchant limits** — IP-based limits catch unauthenticated probing and misconfigured clients before they hit your downstream hosts
- **Document burst allowance explicitly** — burst is intentional headroom above the stated limit; if you set `limit=100` and `burst=20`, tell your merchant docs the limit is 100 with up to 120 in a burst
- **Return `Retry-After` as seconds, not a date** — RFC 7231 allows both, but most payment client libraries parse it as an integer; a date string causes clients to retry immediately on parse failure
- **Never rate-limit your own health check endpoint** — a rate-limited health check causes load balancers to mark your service as unhealthy during traffic spikes, exactly when you need it most
