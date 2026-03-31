---
name: payment-sign
description: Generate and verify payment gateway API signatures (MD5-based hash patterns common in payment gateway integrations). Masks sensitive keys in output.
argument-hint: <gateway-name or 'custom'>
---

Generate or verify payment gateway request signatures. Auto-triggers when working on payment integration code with signature mismatch errors or hash generation.

## Trigger Phrases
"generate signature", "verify hash", "signature mismatch", "payment hash", "vcode", "skey", "api signature wrong"

## Steps

1. **Identify signature type** from $ARGUMENTS or context:
   - Request signature (verify request is from merchant): uses merchant key + order fields
   - Response signature (verify response is from gateway): uses transaction fields + secret key

2. **Collect fields** — prompt for required values if not in context:
   - Common request sig: `merchantId`, `amount`, `orderId`, `verifyKey`
   - Common response sig: `paydate`, `merchantId`, `txnId`, `orderId`, `status`, `amount`, `currency`, `appcode`, `secretKey`

3. **Compute**:
   - Request: `md5(amount + merchantId + orderId + verifyKey)` — coerce all to string, concatenate, lowercase MD5
   - Response step 1: `innerHash = md5(txnId + orderId + status + merchantId + amount + currency)`
   - Response step 2: `skey = md5(paydate + merchantId + innerHash + appcode + secretKey)`

4. **SECURITY**: never display raw `verifyKey` or `secretKey` in output — show as `●●●●●●●●` (8 dots)

5. **If verifying**: compare computed hash to provided hash, flag mismatch clearly

6. **Output**:
   ```
   Request Signature:
   Input:  "{amount}{merchantId}{orderId}{verifyKey}"
   Hash:   a3f8d2c1b9e4f7a6...

   Keys used: verifyKey = ●●●●●●●● (masked)
   ```

## Output Format
- Show concatenation formula
- Show computed hash
- Mask all secret keys
- Flag mismatch with MISMATCH label
