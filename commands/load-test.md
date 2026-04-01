---
name: load-test
description: Generate a k6 load test plan for payment endpoints — ramp to target TPS, test payment submission with realistic payloads, report p95/p99 latency and error rates
allowed_tools: ["Bash", "Read", "Grep", "Glob"]
---

# /load-test

## Goal
Generate a k6 load test script for the payment submission endpoint. The script ramps up to the target TPS, sustains load, then ramps down. It uses test card tokens, includes an idempotency key per request, and enforces thresholds of p95 < 2000ms and error rate < 0.1%.

## Steps
1. If the user has not provided a target TPS, ask:
   > "What is the target TPS (transactions per second) for this load test?"
   Do not proceed until TPS is known.

2. Identify the payment submission endpoint and base URL:
   ```bash
   # Laravel — find the payment POST route
   grep -rn "Route::post" routes/api.php | grep -i "payment\|transaction\|charge"
   # Go — find the HTTP handler registration
   grep -rn "HandleFunc\|POST\|router\." cmd/ internal/ | grep -i "payment\|transaction\|charge"
   ```

3. Identify the request schema (required fields, auth header pattern):
   ```bash
   # Laravel FormRequest rules
   grep -rn "public function rules" app/Http/Requests/ | grep -i "payment\|transaction"
   # Then read the matched file to extract field names
   ```

4. Check whether the project uses Bearer tokens or API key auth:
   ```bash
   grep -rn "Authorization\|api.key\|X-Api-Key" app/Http/Middleware/ routes/api.php config/
   ```

5. Generate the k6 script. Use the target TPS to derive VU counts and stage durations.
   The script must:
   - Use test card token `tok_test_4111111111111111` (never a real PAN)
   - Generate a unique idempotency key per request (`uuidv4()`)
   - Ramp up over 60s → sustain for 120s → ramp down over 30s
   - Set thresholds: `http_req_duration p(95) < 2000`, `http_req_failed rate < 0.001`
   - Report p50, p95, p99 latency and error rate in the summary

   Template (fill in BASE_URL, endpoint path, auth header, and payload fields):
   ```javascript
   import http from 'k6/http';
   import { check, sleep } from 'k6';
   import { uuidv4 } from 'https://jslib.k6.io/k6-utils/1.4.0/index.js';

   // ── Configuration ────────────────────────────────────────────────
   const BASE_URL    = __ENV.BASE_URL    || 'http://localhost:8000';
   const TARGET_TPS  = __ENV.TARGET_TPS  ? parseInt(__ENV.TARGET_TPS) : 50;
   const AUTH_HEADER = __ENV.AUTH_TOKEN
     ? { Authorization: `Bearer ${__ENV.AUTH_TOKEN}` }
     : { 'X-Api-Key': __ENV.API_KEY || 'test-api-key' };

   // k6 derives VUs from TPS * avg_response_time; 1 VU ≈ 1 req/s at <1s latency.
   // Set startVUs conservatively; k6 scales within maxVUs.
   const PEAK_VUS = TARGET_TPS;

   export const options = {
     stages: [
       { duration: '60s',  target: PEAK_VUS },   // ramp up
       { duration: '120s', target: PEAK_VUS },   // sustain
       { duration: '30s',  target: 0 },          // ramp down
     ],
     thresholds: {
       http_req_duration: ['p(95)<2000', 'p(99)<4000'],
       http_req_failed:   ['rate<0.001'],         // < 0.1% errors
     },
   };

   // ── Test card payload (test data only — never use real PANs) ─────
   function buildPayload() {
     return JSON.stringify({
       card_token:      'tok_test_4111111111111111',  // test token
       amount:          1000,                          // minor units, e.g. $10.00
       currency:        'USD',
       merchant_id:     'merchant_test_001',
       reference:       uuidv4(),                     // unique per request
     });
   }

   export default function () {
     const idempotencyKey = uuidv4();

     const res = http.post(
       `${BASE_URL}/api/v1/payments`,
       buildPayload(),
       {
         headers: {
           'Content-Type':  'application/json',
           'Idempotency-Key': idempotencyKey,
           ...AUTH_HEADER,
         },
         timeout: '10s',
       }
     );

     check(res, {
       'status is 200 or 201':     (r) => r.status === 200 || r.status === 201,
       'response has transaction':  (r) => JSON.parse(r.body)?.transaction_id !== undefined,
       'no server error':           (r) => r.status < 500,
     });

     // No sleep — let k6 stages control concurrency
   }
   ```

6. Provide the run command for the generated script:
   ```bash
   # Basic run
   BASE_URL=https://staging.payments.internal \
   AUTH_TOKEN=<staging-token> \
   TARGET_TPS=50 \
   k6 run load-tests/payment-submit.js

   # With output to InfluxDB/Grafana (optional)
   k6 run --out influxdb=http://localhost:8086/k6 load-tests/payment-submit.js
   ```

7. Save the generated script to `load-tests/payment-submit.js` (create the directory if absent).

8. After generation, remind the user:
   - Run against staging only — never production
   - Rotate the `AUTH_TOKEN` after the test
   - The test card token `tok_test_4111111111111111` must never be replaced with a real PAN

## Output
```
LOAD TEST PLAN — payment submission endpoint
────────────────────────────────────────────────────────────────────
Target TPS:        50
Endpoint:          POST /api/v1/payments
Auth:              Bearer token (env: AUTH_TOKEN)
Card token:        tok_test_4111111111111111  [TEST DATA]
Idempotency key:   uuidv4() per request

Stages:
  Ramp up:   0 → 50 VUs over 60s
  Sustain:   50 VUs for 120s
  Ramp down: 50 → 0 VUs over 30s
  Total duration: ~3m 30s

Thresholds:
  p(95) latency < 2000ms
  p(99) latency < 4000ms
  Error rate    < 0.1%

Script written to: load-tests/payment-submit.js

Run:
  BASE_URL=https://staging.payments.internal \
  AUTH_TOKEN=<staging-token> \
  TARGET_TPS=50 \
  k6 run load-tests/payment-submit.js

────────────────────────────────────────────────────────────────────
REMINDER: Run against staging only. Rotate AUTH_TOKEN after the test.
────────────────────────────────────────────────────────────────────
```
