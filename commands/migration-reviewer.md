



---
description: Review an API migration MR by comparing new Laravel controller responses against the legacy PHP code, then post findings as a GitLab MR comment
---

## Context

- Working directory: !`pwd`
- Current branch: !`git branch --show-current`

## Your task

You are reviewing a migration MR that ports legacy PHP API code into the Laravel api-v2 framework. Your goal is to verify that every response — fields, formats, edge cases, and error messages — exactly matches the old code.

The user will supply:
1. **MR URL or IID**
2. **Legacy file path** — the old PHP entry point being replaced

If either is missing, ask before proceeding.

---

### Step 1 — Fetch the MR diff

Use `mcp__plugin_gitlab_gitlab__get_merge_request_diffs` with:
- `id`: `Backend/api-v2/web`
- `merge_request_iid`: the MR IID

Also fetch the MR description with `mcp__plugin_gitlab_gitlab__get_merge_request` to understand scope.

List all changed/added files from the diff. Identify:
- The new controller(s) and trait(s)
- The new service(s)
- The routing entry (routes file)

---

### Step 2 — Read the legacy code

Read the legacy entry point file. If it `include()`s version-specific sub-files (e.g. `daily_report_v1.php`, `daily_report_v2.php`), read **all of them**. Build a per-version understanding of:

1. **Input parameters** accepted (GET/POST)
2. **Authentication / skey validation** logic and hash algorithm per merchant/setting
3. **SQL queries** — tables, date range logic, archive fallback, pagination
4. **Field selection** — default fields, additional fields, hidden fields (`BIN`, etc.)
5. **Field processing** — formatting rules per field key:
   - `bill_amt` → `number_format($v, 2, '.', '')`
   - `billing_info` → strip Bank Name suffix, strip newlines
   - `StatCode` → `00/11/22` mapping
   - `channel` → RPP_DuitNowQR → def_channel substitution
   - `status_desc` → split on `Return Data`, format per sub-field (StatusDescription, ResponseCode, BuyerName, BankTransactionID, BankDateTime, etc.)
   - GST / NetAmount → date-range gated calculation (2015-04-01 to 2018-06-01)
   - BankName → extract from billing_info or bin_2_card lookup
   - Card fields (CardScheme, CardType, CardCountry) — BIN lookup logic
6. **Response format** — text (TSV with header), JSON, CSV (with headers), and which formats each version supports
7. **Special merchant handling** — e.g. `ukm` field set, CDC group, sha512 merchants
8. **Side effects** — CouchDB writes, Gearman tasks, file uploads (S3, SFTP)
9. **Error messages** — exact strings and HTTP status (old code always returned 200)

---

### Step 3 — Read the new code

Read the new controller files, traits, and services introduced in the MR diff. For each version controller, map the same 9 points above.

Pay special attention to:
- Methods moved from traits to services — verify no behaviour was silently dropped
- Method signature changes (removed parameters often remove guard conditions)
- PHP `match` expressions — multi-arm match (comma-separated keys) is valid PHP 8 but verify all arms are present
- `$transaction[$fieldKey] ?? null` vs `$row[$kfs]` — nullability differences
- `generateResponse()` output format — verify TSV header/row structure matches legacy `echo $colsH."\n"; echo $result;`
- HTTP status codes — new code returns 400/500; old code returned 200 always

---

### Step 4 — Compare and identify issues

Cross-reference every field and code path. Use this checklist:

**Authentication**
- [ ] Hash algorithm matches per merchant and per vcode_setting
- [ ] sha512-forced merchants list is identical
- [ ] Error message text matches exactly

**Field processing**
- [ ] Every field in `processField()` / `$fieldProcessors` has a case for each version
- [ ] `bill_amt` formatted with `number_format` in all versions
- [ ] `billing_info` strips newlines AND truncates at "Bank Name"
- [ ] `channel` substitutes `RPP_DuitNowQR` → `def_channel`
- [ ] `status_desc` guard condition preserved (old: check for "Return Data" before parsing)
- [ ] `BankDateTime` for FPX returns `date('Y-m-d H:i:s', strtotime(...))` not raw value
- [ ] BankName extraction order: billing_info first, then bin_2_card fallback
- [ ] GST/NetAmount date-range gate matches (`2015-04-01` to `2018-06-01`)
- [ ] Card fields (CardScheme/CardType/CardCountry) — indicator BIN lookup + fallback logic

**Queries**
- [ ] Date range calculation matches (rdate + rduration, default 86400 seconds)
- [ ] Archive table fallback (`A_transaction`) present where old code had it
- [ ] Pagination (`LIMIT`/`OFFSET` with `page` param) present in versions that had it
- [ ] `status_desc` added to query fields when accessed
- [ ] `def_channel` added to query fields

**Response format**
- [ ] Text: tab-separated with header row, empty values as "None"
- [ ] JSON: `json_encode` structure matches (array of objects, or array of arrays for AliPay PDS)
- [ ] CSV: header row included, values properly escaped
- [ ] Versions that support each format match the old code

**Side effects**
- [ ] CouchDB writes (gearman tasks) are present and wrapped in try-catch
- [ ] S3/SFTP file upload (`uploadToS3` response_type) present where applicable
- [ ] Summary data structure (totalCount, successCount, failCount) matches

**Special cases**
- [ ] UKM merchant field set (includes GST, Transaction Fee, Net Amount columns)
- [ ] CDC group merchants (`cdc4_Dev`, `eperolehanreg`, `eperolehancart`) — BankDateTime extra channels
- [ ] AirAsia: two-query logic (create_date query + paid_date query + refunds query)
- [ ] AirAsia: CYBERSOURCE BankMID uses `subMer_ID` with pbb_ prefix check
- [ ] AirAsia: AcquirerName returns "Public Bank" for CYBERSOURCE, "Fiuu" otherwise
- [ ] AirAsia: `history` field parsed to extract UpdateDate for current status
- [ ] AliPay PDS: JSON response includes header row as first element
- [ ] Affin: reconciliation summary pushed to CouchDB with correct structure

**Error handling**
- [ ] HTTP status change (200 → 400/500) is intentional and documented
- [ ] No methods called that no longer exist after trait/service refactor

---

### Step 5 — Compile findings

Group issues by severity:

- 🔴 **Critical** — fatal error at runtime, or wrong data returned silently
- 🟠 **High** — behavioural regression that changes merchant output
- 🟡 **Medium** — breaking change requiring merchant/deployment comms
- 🔵 **Low** — edge case, minor inconsistency, or missing defensive guard

For each issue include:
- What the old code did
- What the new code does
- Which file and method
- A concrete fix (code snippet when helpful)

Also note what is **correctly migrated**.

---

### Step 6 — Post comment to GitLab MR

Format the full review as a GitLab markdown comment (use the structure from Step 5).

Since the GitLab MCP `create_workitem_note` tool only supports Issues (not MRs), output the comment text directly to the user so they can paste it into the MR. Format it clearly with:

```
## Code Review — [API name] Migration vs Legacy [filename]

### 🔴 Critical Bugs
...

### 🟠 High — Behavior Regressions
...

### 🟡 Medium
...

### 🔵 Low
...

### ✅ What's Correct
...

### Summary Table
| # | Issue | Severity | File |
```

---

### Notes

- Always read the **full** legacy file content, not just the entry point — version sub-files contain the real logic
- The `processBinAndChannel` / BIN lookup pattern appears across all V3+ versions — verify each controller wires it correctly
- Deleted traits mean all their methods must be accounted for somewhere — grep for every public method name before concluding it was moved vs dropped
- The `$returnDataExists` guard pattern in old code (`strpos($status_desc, 'Return Data') !== false`) protects against bad array index access — verify new code preserves this safety
 
