---
name: settlement-check
description: Validate today's settlement batch against the transaction database — compare counts and amounts, flag mismatches, produce a variance report
allowed_tools: ["Bash", "Read", "Grep", "Glob"]
---

# /settlement-check

## Goal
Validate today's settlement batch against the transaction database. Compare counts and totals, flag amount mismatches greater than 0.01, identify transactions present in the DB but absent from the settlement file, and identify items in the settlement file but absent from the DB. Produce a variance report.

## Steps
1. Locate the settlement file for today:
   ```bash
   # Adjust path pattern to match your settlement file location and naming convention
   ls -1t storage/settlements/ | head -5
   # Common naming: YYYYMMDD.csv, settlement_YYYYMMDD.csv, etc.
   ```
2. Count approved transactions in the DB for today:
   ```bash
   php artisan tinker --execute="
     \$date  = now()->toDateString();
     \$count  = DB::table('transactions')
                  ->whereDate('created_at', \$date)
                  ->where('status', 'approved')
                  ->count();
     \$total  = DB::table('transactions')
                  ->whereDate('created_at', \$date)
                  ->where('status', 'approved')
                  ->sum('amount');
     echo \"DB approved — count: {\$count}  total: {\$total}\n\";
   "
   ```
3. Count and sum the settlement file:
   ```bash
   # Assumes CSV with header; adjust column indices to match your file format
   # Column 1 = transaction_id, Column 2 = amount (adjust as needed)
   SETTLEMENT_FILE="storage/settlements/$(date +%Y%m%d).csv"
   SETTLE_COUNT=$(tail -n +2 "$SETTLEMENT_FILE" | wc -l | tr -d ' ')
   SETTLE_TOTAL=$(tail -n +2 "$SETTLEMENT_FILE" | awk -F',' '{sum += $2} END {printf "%.2f", sum}')
   echo "Settlement file — count: $SETTLE_COUNT  total: $SETTLE_TOTAL"
   ```
4. Flag amount mismatches greater than 0.01 between DB and settlement file (per transaction):
   ```bash
   php artisan tinker --execute="
     \$date = now()->toDateString();
     \$dbTxns = DB::table('transactions')
                   ->whereDate('created_at', \$date)
                   ->where('status', 'approved')
                   ->pluck('amount', 'id');
     // Load settlement file amounts (adjust path and CSV column indices)
     \$settlePath = storage_path('settlements/' . now()->format('Ymd') . '.csv');
     \$settle = [];
     if (file_exists(\$settlePath)) {
       \$lines = array_slice(file(\$settlePath), 1); // skip header
       foreach (\$lines as \$line) {
         \$cols = str_getcsv(trim(\$line));
         \$settle[\$cols[0]] = (float) \$cols[1]; // id => amount
       }
     }
     foreach (\$dbTxns as \$id => \$dbAmt) {
       if (isset(\$settle[\$id])) {
         \$diff = abs(\$dbAmt - \$settle[\$id]);
         if (\$diff > 0.01) {
           echo \"MISMATCH  tx_id={\$id}  db={\$dbAmt}  settle={\$settle[\$id]}  diff={\$diff}\n\";
         }
       }
     }
   "
   ```
5. List transaction IDs present in the DB but missing from the settlement file:
   ```bash
   php artisan tinker --execute="
     \$date = now()->toDateString();
     \$dbIds = DB::table('transactions')
                  ->whereDate('created_at', \$date)
                  ->where('status', 'approved')
                  ->pluck('id')
                  ->map(fn(\$id) => (string) \$id)
                  ->toArray();
     \$settlePath = storage_path('settlements/' . now()->format('Ymd') . '.csv');
     \$settleIds = [];
     if (file_exists(\$settlePath)) {
       \$lines = array_slice(file(\$settlePath), 1);
       foreach (\$lines as \$line) {
         \$cols = str_getcsv(trim(\$line));
         \$settleIds[] = \$cols[0];
       }
     }
     \$missing = array_diff(\$dbIds, \$settleIds);
     echo count(\$missing) . \" transactions in DB but NOT in settlement file:\n\";
     foreach (array_slice(\$missing, 0, 20) as \$id) { echo \"  tx_id={\$id}\n\"; }
     if (count(\$missing) > 20) echo '  ... (truncated)\n';
   "
   ```
6. List items in the settlement file but missing from the DB:
   ```bash
   php artisan tinker --execute="
     \$date = now()->toDateString();
     \$dbIds = DB::table('transactions')
                  ->whereDate('created_at', \$date)
                  ->where('status', 'approved')
                  ->pluck('id')
                  ->map(fn(\$id) => (string) \$id)
                  ->toArray();
     \$settlePath = storage_path('settlements/' . now()->format('Ymd') . '.csv');
     \$settleIds = [];
     if (file_exists(\$settlePath)) {
       \$lines = array_slice(file(\$settlePath), 1);
       foreach (\$lines as \$line) {
         \$cols = str_getcsv(trim(\$line));
         \$settleIds[] = \$cols[0];
       }
     }
     \$orphans = array_diff(\$settleIds, \$dbIds);
     echo count(\$orphans) . \" items in settlement file but NOT in DB:\n\";
     foreach (array_slice(\$orphans, 0, 20) as \$id) { echo \"  tx_id={\$id}\n\"; }
     if (count(\$orphans) > 20) echo '  ... (truncated)\n';
   "
   ```
7. Summarise findings and flag the batch as PASS, WARNING, or FAIL:
   - PASS: counts match, totals match within 0.01, zero missing on either side
   - WARNING: counts match, 1–5 missing transactions or small variance
   - FAIL: count mismatch > 1%, total variance > 1.00, or orphan items in settlement file

## Output
```
SETTLEMENT CHECK — 2026-04-01
────────────────────────────────────────────────────────────────────
              DB (approved)     Settlement file     Variance
Count:        8,412             8,410               -2
Total (USD):  1,204,388.50      1,204,381.00        -7.50

Amount mismatches (diff > 0.01):
  tx_id=TXN-00482  db=150.00  settle=149.95  diff=0.05
  tx_id=TXN-01837  db=75.00   settle=74.99   diff=0.01 (at threshold)

In DB but NOT in settlement file (2 transactions):
  tx_id=TXN-09901
  tx_id=TXN-09902

In settlement file but NOT in DB (0 items):
  none

────────────────────────────────────────────────────────────────────
VERDICT: WARNING
  2 transactions missing from settlement file.
  Review TXN-09901 and TXN-09902 — check if they were approved after
  the settlement cut-off or if the settlement process silently dropped them.
────────────────────────────────────────────────────────────────────
```
