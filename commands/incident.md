---
name: incident
description: Start an incident runbook for a payment outage — gather error rates, identify affected merchants, check host health, determine rollback point
allowed_tools: ["Bash", "Read", "Grep", "Glob"]
---

# /incident

## Goal
Run the payment incident runbook. Gather error rates from logs, identify affected merchants and channels, check payment host connectivity, determine when failures started, and produce a structured incident summary with a rollback or escalation recommendation.

## Steps
1. Check recent error logs:
   ```bash
   # Laravel log tail — last 200 lines
   tail -200 storage/logs/laravel.log | grep -E "ERROR|CRITICAL|Exception|host|timeout|refused"
   # Go service log (adjust path to match project)
   tail -200 /var/log/payment-service/app.log | grep -E "ERROR|FATAL|timeout|refused"
   ```
2. Query transaction failure rate for the last 30 minutes:
   ```bash
   # Adjust DB credentials and table name to match project
   php artisan tinker --execute="
     \$window = now()->subMinutes(30);
     \$total  = DB::table('transactions')->where('created_at', '>=', \$window)->count();
     \$failed = DB::table('transactions')->where('created_at', '>=', \$window)
                 ->whereIn('status', ['failed','error','declined'])->count();
     \$rate   = \$total > 0 ? round(\$failed / \$total * 100, 2) : 0;
     echo \"Total: {\$total}  Failed: {\$failed}  Error rate: {\$rate}%\n\";
   "
   ```
3. Identify when failures started:
   ```bash
   # Find earliest failed transaction timestamp in the last 2 hours
   php artisan tinker --execute="
     \$tx = DB::table('transactions')
               ->whereIn('status', ['failed','error'])
               ->where('created_at', '>=', now()->subHours(2))
               ->orderBy('created_at')
               ->first();
     echo \$tx ? \"First failure: {\$tx->created_at} (ID: {\$tx->id})\n\" : \"No failures in last 2h\n\";
   "
   ```
4. Check payment host health endpoint:
   ```bash
   # Replace URL with the actual host health endpoint
   curl -o /dev/null -s -w "HTTP %{http_code}  time %{time_total}s\n" \
     --max-time 5 https://payment-host.internal/health
   ```
5. List affected merchant IDs (top 10 by failure count):
   ```bash
   php artisan tinker --execute="
     DB::table('transactions')
       ->select('merchant_id', DB::raw('count(*) as failures'))
       ->whereIn('status', ['failed','error'])
       ->where('created_at', '>=', now()->subMinutes(30))
       ->groupBy('merchant_id')
       ->orderByDesc('failures')
       ->limit(10)
       ->get()
       ->each(fn(\$r) => print \"Merchant: {\$r->merchant_id}  Failures: {\$r->failures}\n\");
   "
   ```
6. Identify affected channels (card scheme / channel field if present):
   ```bash
   php artisan tinker --execute="
     DB::table('transactions')
       ->select('channel', DB::raw('count(*) as failures'))
       ->whereIn('status', ['failed','error'])
       ->where('created_at', '>=', now()->subMinutes(30))
       ->groupBy('channel')
       ->orderByDesc('failures')
       ->get()
       ->each(fn(\$r) => print \"Channel: {\$r->channel}  Failures: {\$r->failures}\n\");
   "
   ```
7. Determine the last known-good deployment:
   ```bash
   git log --oneline -10
   # Note the commit hash immediately before failures started
   ```
8. Recommend rollback or escalation based on findings:
   - If error rate > 20% and host health endpoint is non-200: recommend rollback to last-good commit and page on-call host team
   - If error rate > 5% but host is healthy: check application logs for regression, consider rollback
   - If error rate < 5%: monitor for 5 minutes, escalate if trend is rising

## Output
```
INCIDENT RUNBOOK — Payment Outage
────────────────────────────────────────────────────────────────────
Started:       2026-04-01 03:42 UTC (first failed transaction)
Duration:      ~18 minutes ongoing

Error Rate (last 30 min):
  Total transactions:   1,204
  Failed transactions:  487
  Error rate:           40.4%

Host Health:
  GET https://payment-host.internal/health → HTTP 503  time 5.001s (TIMEOUT)

Affected Merchants (top 5):
  merchant_id=1042   failures=112
  merchant_id=0891   failures=98
  merchant_id=2210   failures=76
  merchant_id=0055   failures=71
  merchant_id=1337   failures=44

Affected Channels:
  VISA    failures=301
  MC      failures=142
  AMEX    failures=44

Recent Deployments:
  a3f91b2  feat(host): increase TCP timeout to 60s   (2026-04-01 03:38 UTC)
  d82c014  chore(deps): bump guzzlehttp/guzzle        (2026-03-31 18:10 UTC)

────────────────────────────────────────────────────────────────────
RECOMMENDATION: ROLLBACK
  Host health failing — likely upstream issue compounded by recent timeout change.
  Rollback: git revert a3f91b2 && deploy
  Escalate: page payment-host on-call immediately
────────────────────────────────────────────────────────────────────
```
