---
name: mcp-server-patterns
description: MCP server patterns for payment systems — tool definitions with Zod schemas, transaction lookup and refund tools, merchant summary resources, payment workflow prompts, and security rules for PCI-safe MCP data access.
origin: fintech-stack
---

# MCP Server Patterns

MCP tools that access payment data carry the same PCI obligations as any other payment API. A tool that returns a full PAN is a compliance violation regardless of who calls it. This skill covers the patterns for building payment MCP tools that are useful to Claude without exposing cardholder data.

## When to Activate

- Building or extending an MCP server for payment tools
- Adding transaction lookup, status check, or refund tools to an MCP server
- Reviewing MCP tool definitions for security issues
- Developer asks "how do I expose payment data via MCP?" or "how do I add an MCP tool?"

---

## Server Setup

```typescript
// src/server.ts
import { McpServer } from '@anthropic-ai/mcp-server'
import { z } from 'zod'

const server = new McpServer({
  name: 'payment-mcp',
  version: '1.0.0',
})

// Register tools, resources, and prompts below
server.start()
```

---

## Tool: Transaction Lookup

```typescript
server.tool(
  'get_transaction',
  'Look up a payment transaction by ID. Returns status, amount, and masked card details — never full PAN.',
  {
    transaction_id: z.string().describe('Transaction ID (e.g., txn_01HXYZ)'),
    merchant_id: z.string().optional().describe('Optional merchant ID to scope the lookup'),
  },
  async ({ transaction_id, merchant_id }) => {
    const txn = await db.transactions.findById(transaction_id, { merchant_id })

    if (!txn) {
      return {
        content: [{ type: 'text', text: `Transaction ${transaction_id} not found` }],
        isError: true,
      }
    }

    return {
      content: [{
        type: 'text',
        text: JSON.stringify({
          id:         txn.id,
          status:     txn.status,
          amount:     txn.amount,
          currency:   txn.currency,
          card_last4: txn.card_last4,   // last 4 only — never full PAN
          card_brand: txn.card_brand,
          auth_code:  txn.auth_code,
          created_at: txn.created_at,
        }, null, 2),
      }],
    }
  }
)
```

---

## Tool: Payment Status Check

```typescript
server.tool(
  'check_payment_status',
  'Check the current status of a payment by merchant order reference.',
  {
    order_ref:   z.string().describe('Merchant order reference'),
    merchant_id: z.string().describe('Merchant ID'),
  },
  async ({ order_ref, merchant_id }) => {
    const txn = await db.transactions.findByOrderRef(order_ref, merchant_id)

    if (!txn) {
      return {
        content: [{ type: 'text', text: `No transaction found for order ${order_ref}` }],
        isError: true,
      }
    }

    const messages: Record<string, string> = {
      approved: `Payment approved. Auth code: ${txn.auth_code}`,
      declined: 'Payment was declined by the issuer.',
      pending:  'Payment is pending — host response not yet received.',
      reversed: 'Payment was reversed.',
      refunded: `Payment refunded. Refund amount: ${txn.refund_amount}`,
    }

    return {
      content: [{ type: 'text', text: messages[txn.status] ?? `Unknown status: ${txn.status}` }],
    }
  }
)
```

---

## Tool: Refund (Queue for Human Approval)

```typescript
server.tool(
  'initiate_refund',
  'Create a refund request for an approved transaction. Queues for human approval — does not execute immediately.',
  {
    transaction_id: z.string().describe('Transaction ID to refund'),
    amount: z.number().int().positive().describe('Refund amount in minor units (cents)'),
    reason: z.string().max(100).describe('Reason for refund'),
  },
  async ({ transaction_id, amount, reason }) => {
    const txn = await db.transactions.findById(transaction_id)

    if (!txn || txn.status !== 'approved') {
      return {
        content: [{ type: 'text', text: 'Transaction not found or not eligible for refund' }],
        isError: true,
      }
    }

    if (amount > txn.amount) {
      return {
        content: [{ type: 'text', text: `Refund amount (${amount}) exceeds original (${txn.amount})` }],
        isError: true,
      }
    }

    // Queue for human approval — never execute a refund automatically from an AI tool
    const refundRequest = await db.refundRequests.create({
      transaction_id,
      amount,
      reason,
      status: 'pending_approval',
    })

    return {
      content: [{
        type: 'text',
        text: `Refund request ${refundRequest.id} created for ${amount} ${txn.currency}. Pending human approval.`,
      }],
    }
  }
)
```

---

## Resource: Merchant Transaction Summary

```typescript
server.resource(
  'merchant-summary',
  'merchant-summary://{merchant_id}',
  async (uri) => {
    const merchantId = uri.pathname.replace(/^\/\//, '')
    const summary = await db.transactions.getSummary(merchantId)

    return {
      contents: [{
        uri: uri.href,
        mimeType: 'application/json',
        text: JSON.stringify({
          merchant_id:    merchantId,
          total_today:    summary.totalToday,
          approved_today: summary.approvedToday,
          declined_today: summary.declinedToday,
          // No card data — aggregate summary only
        }, null, 2),
      }],
    }
  }
)
```

---

## Prompt: Decline Investigation

```typescript
server.prompt(
  'investigate_decline',
  'Generate a structured investigation plan for a declined payment',
  { transaction_id: z.string() },
  async ({ transaction_id }) => ({
    messages: [{
      role: 'user',
      content: {
        type: 'text',
        text: `Please investigate the decline for transaction ${transaction_id}.
               Look up the transaction details, check the response code,
               and suggest resolution steps for the merchant.`,
      },
    }],
  })
)
```

---

## Error Handling Wrapper

```typescript
async function safeToolHandler<T>(
  fn: () => Promise<T>
): Promise<{ content: Array<{ type: string; text: string }>; isError?: boolean }> {
  try {
    return await fn() as any
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Unexpected error'
    return {
      content: [{ type: 'text', text: `Error: ${message}` }],
      isError: true,
    }
  }
}
```

---

## Best Practices

- **Never return full PAN, CVV, or track data** — return `card_last4` only; full card data through an MCP tool is a PCI violation
- **Scope every query by `merchant_id`** — cross-merchant data access via an MCP tool is a security issue, not just a bug
- **Refund and void tools queue for human approval** — never have an AI tool execute a financial transaction automatically
- **Validate all inputs with Zod before database access** — even if Claude is the caller, treat input as untrusted
- **Log every MCP tool invocation** — same audit trail requirements as a payment API call
- **Tool name in `snake_case`, description includes side effects** — if a tool creates a record, the description must say so
