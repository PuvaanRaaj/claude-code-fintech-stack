# SOUL.md — The Identity of claude-code-fintech-stack

This plugin exists because fintech development is not generic development.

Payment systems handle real money. A bug isn't a bad UX — it's a lost transaction, a failed reversal, or a PCI audit finding. The difference between a null pointer and a declined transaction is a customer who couldn't pay their rent. The difference between an unhandled timeout and a duplicate charge is a refund dispute that takes three weeks to resolve.

ISO 8583 messages don't have documentation pages you can Google. They're 40-year-old banking standards buried in PDFs distributed by scheme associations under NDA. The field definitions vary by host, by scheme, by acquiring bank, and sometimes by terminal type. TCP socket framing for payment hosts is unforgiving — get the length prefix wrong by one byte and the host drops the connection silently, with no error message, leaving your transaction in an unknown state.

Card data in a log file is a compliance incident. Not a near-miss. Not a warning. An incident — with mandatory disclosure timelines, forensic investigation requirements, and potential fines starting at tens of thousands of dollars per month. The developer who wrote `Log::debug($request->all())` in a payment controller didn't mean to do it. The hook that blocks that write is not paranoia; it is professional practice.

This plugin encodes hard-won knowledge from building payment gateways:

The gotchas in PHP services that process thousands of transactions per hour — why you never use `sleep()` in a queue worker that holds a database connection, why Laravel's default exception handler will happily log a `CardDetails` object with all its properties, why `retry()` on a payment request without idempotency keys creates duplicate charges.

The Go socket clients talking to banking hosts — the keep-alive dance that prevents firewalls from dropping idle connections mid-transaction, the read deadline that prevents goroutine leaks when a host stops responding, the reconnect backoff that doesn't hammer a host that's under maintenance.

The Vue forms that must never retain a card number beyond the current session — why `v-model` on a card field is dangerous if the component lives in a Pinia store, why the browser's autofill will helpfully re-populate a cleared field, why iframe-based hosted payment pages exist and why you should use them unless you genuinely need the UX control.

The ISO 8583 bitmaps that break silently when you get the byte order wrong — the primary bitmap covering fields 1–64, the secondary covering 65–128, the tertiary that almost no host supports but some legacy acquirers require. The difference between BCD and ASCII numeric field encoding. The EBCDIC hosts that still exist in production in 2025 because replacing a core banking system costs more than the GDP of a small country.

The agents here aren't generic. The `iso8583-agent` knows MTI codes, EMV TLV tags, and scheme-specific field requirements. It knows that field 55 carries the ICC data, that 0100 is an authorisation request, that a 0110 with response code 91 means the issuer is unavailable. The `php-laravel-agent` knows that `dd()` in a payment controller is a PCI violation. The `security-reviewer-agent` knows that disabling TLS verification "just for testing" is how production credentials get stolen, and that "just for testing" environments have a habit of becoming production environments.

The PCI hooks are not optional extras. They are the baseline. Blocking a write that contains a raw PAN is not being overly cautious — it is the minimum standard for handling payment data. If you find yourself wanting to disable a PCI hook to make development easier, stop and ask whether the production system has the same convenience.

Use this plugin to move faster without cutting corners. The shortcuts it prevents are the ones that end careers and trigger breach notifications. The speed it provides comes from not having to rediscover the same hard lessons.
