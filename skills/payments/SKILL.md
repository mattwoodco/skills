---
name: payments
description: Credit-based billing with Stripe — subscriptions, credit balance, usage metering, checkout, billing portal. Use this skill when the user says "add payments", "setup billing", "add stripe", "setup credits", "subscription billing", or "stripe integration".
author: "@mattwoodco"
version: 2.0.1
created: 2026-02-13
updated: 2026-02-13
dependencies: [auth, db, env-config, docker]
---

# Payments (Stripe)

Credit-based billing using [Stripe](https://stripe.com). Subscription plans (free/pro/team) with monthly credit allocations, one-time credit purchases, usage metering, and full webhook handling. Local development with Stripe CLI via Docker.

## Prerequisites

- Next.js app with App Router (no `src/` directory)
- `auth` skill applied (for user authentication)
- `db` skill applied (Drizzle + Postgres)
- `env-config` skill applied
- `docker` skill applied (for Stripe CLI)

## Installation

```bash
bun add stripe @stripe/stripe-js
```

## Environment Variables

Add to `.env.local`:

```env
# Stripe
STRIPE_SECRET_KEY=sk_test_...
NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY=pk_test_...
STRIPE_WEBHOOK_SECRET=whsec_...
```

Add to `env.ts`:

```typescript
// Server schema
STRIPE_SECRET_KEY: z.string().startsWith("sk_"),
STRIPE_WEBHOOK_SECRET: z.string().startsWith("whsec_"),

// Client schema
NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY: z.string().startsWith("pk_"),
```

## Docker Setup

Add Stripe CLI to `docker-compose.yml`:

```yaml
services:
  stripe-cli:
    image: stripe/stripe-cli:latest
    command: listen --forward-to http://host.docker.internal:3000/api/stripe/webhook --api-key ${STRIPE_SECRET_KEY}
    environment:
      - STRIPE_API_KEY=${STRIPE_SECRET_KEY}
    extra_hosts:
      - "host.docker.internal:host-gateway"
    profiles:
      - dev
```

Start with:

```bash
docker compose --profile dev up stripe-cli
```

## What Gets Created

```
app/
├── api/
│   ├── stripe/
│   │   └── webhook/
│   │       └── route.ts            # Stripe webhook handler
│   └── billing/
│       ├── route.ts                # GET subscription + balance
│       ├── checkout/
│       │   └── route.ts            # POST create checkout session
│       └── portal/
│           └── route.ts            # POST create billing portal
lib/
└── payments/
    ├── stripe.ts                   # Stripe client setup
    ├── plans.ts                    # Plan definitions and credit costs
    ├── credits.ts                  # Credit balance helpers
    └── client.ts                   # Client-side helpers
db/
└── schema/
    ├── subscriptions.ts            # Subscriptions table
    └── credit-transactions.ts      # Credit ledger table
components/
└── billing/
    ├── plan-selector.tsx           # Plan comparison cards
    ├── credit-balance.tsx          # Credit balance badge
    └── upgrade-dialog.tsx          # Upgrade prompt dialog
```

## Setup Steps

### Step 1: Create `db/schema/subscriptions.ts`

```typescript
import { pgTable, text, integer, timestamp, boolean, uuid } from "drizzle-orm/pg-core";

export const subscriptions = pgTable("subscriptions", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: text("user_id").notNull().unique(),
  stripeCustomerId: text("stripe_customer_id").notNull(),
  stripeSubscriptionId: text("stripe_subscription_id"),
  stripePriceId: text("stripe_price_id"),
  plan: text("plan", {
    enum: ["free", "pro", "team"],
  }).notNull().default("free"),
  status: text("status", {
    enum: ["active", "past_due", "canceled", "trialing"],
  }).notNull().default("active"),
  creditBalance: integer("credit_balance").notNull().default(0),
  currentPeriodStart: timestamp("current_period_start"),
  currentPeriodEnd: timestamp("current_period_end"),
  cancelAtPeriodEnd: boolean("cancel_at_period_end").default(false),
  createdAt: timestamp("created_at").defaultNow().notNull(),
  updatedAt: timestamp("updated_at").defaultNow().notNull(),
});

export type Subscription = typeof subscriptions.$inferSelect;
export type NewSubscription = typeof subscriptions.$inferInsert;
```

### Step 2: Create `db/schema/credit-transactions.ts`

```typescript
import { pgTable, text, integer, timestamp, uuid } from "drizzle-orm/pg-core";

export const creditTransactions = pgTable("credit_transactions", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: text("user_id").notNull(),
  amount: integer("amount").notNull(),
  type: text("type", {
    enum: ["credit", "debit"],
  }).notNull(),
  source: text("source", {
    enum: ["subscription", "purchase", "usage", "bonus", "refund"],
  }).notNull(),
  sourceId: text("source_id"),
  description: text("description"),
  createdAt: timestamp("created_at").defaultNow().notNull(),
});

export type CreditTransaction = typeof creditTransactions.$inferSelect;
export type NewCreditTransaction = typeof creditTransactions.$inferInsert;
```

### Step 3: Add exports to `db/schema/index.ts`

```typescript
export * from "./subscriptions";
export * from "./credit-transactions";
```

### Step 4: Create `lib/payments/stripe.ts`

```typescript
import Stripe from "stripe";

const stripeKey = process.env.STRIPE_SECRET_KEY;
if (!stripeKey) throw new Error("STRIPE_SECRET_KEY is required");

export const stripe = new Stripe(stripeKey, {
  apiVersion: "2026-01-28.clover",
  typescript: true,
});

export async function getOrCreateCustomer(params: {
  userId: string;
  email: string;
  name?: string;
}): Promise<Stripe.Customer> {
  const existing = await stripe.customers.list({
    email: params.email,
    limit: 1,
  });

  if (existing.data.length > 0) {
    return existing.data[0];
  }

  return stripe.customers.create({
    email: params.email,
    name: params.name,
    metadata: { userId: params.userId },
  });
}
```

### Step 5: Create `lib/payments/plans.ts`

```typescript
export type PlanName = "free" | "pro" | "team";

export type PlanConfig = {
  name: string;
  description: string;
  monthlyCredits: number;
  priceMonthly: number;
  features: string[];
};

export const PLANS: Record<PlanName, PlanConfig> = {
  free: {
    name: "Free",
    description: "Get started with basic features",
    monthlyCredits: 50,
    priceMonthly: 0,
    features: [
      "50 credits/month",
      "Basic image generation",
      "Community support",
    ],
  },
  pro: {
    name: "Pro",
    description: "For professionals and creators",
    monthlyCredits: 500,
    priceMonthly: 29,
    features: [
      "500 credits/month",
      "All models (Flux Pro, SDXL, etc.)",
      "Video generation",
      "Priority processing",
      "Email support",
    ],
  },
  team: {
    name: "Team",
    description: "For teams and businesses",
    monthlyCredits: 2000,
    priceMonthly: 99,
    features: [
      "2,000 shared credits/month",
      "All Pro features",
      "Real-time collaboration",
      "Team admin dashboard",
      "Priority support",
    ],
  },
};

export type OperationType =
  | "image-generation"
  | "image-generation-pro"
  | "video-generation"
  | "image-to-image"
  | "inpainting";

export const CREDIT_COSTS: Record<OperationType, number> = {
  "image-generation": 1,
  "image-generation-pro": 5,
  "video-generation": 20,
  "image-to-image": 2,
  "inpainting": 3,
};
```

### Step 6: Create `lib/payments/credits.ts`

```typescript
import { db } from "@/db";
import { subscriptions, creditTransactions } from "@/db/schema";
import { eq, sql } from "drizzle-orm";
import type { OperationType } from "./plans";
import { CREDIT_COSTS } from "./plans";

export async function getBalance(userId: string): Promise<number> {
  const [sub] = await db
    .select({ creditBalance: subscriptions.creditBalance })
    .from(subscriptions)
    .where(eq(subscriptions.userId, userId))
    .limit(1);

  return sub?.creditBalance ?? 0;
}

export async function hasCredits(
  userId: string,
  operation: OperationType,
  quantity = 1
): Promise<boolean> {
  const balance = await getBalance(userId);
  return balance >= CREDIT_COSTS[operation] * quantity;
}

export async function deductCredits(params: {
  userId: string;
  operation: OperationType;
  quantity?: number;
  description?: string;
}): Promise<{ success: boolean; cost: number; newBalance: number; error?: string }> {
  const { userId, operation, quantity = 1, description } = params;
  const cost = CREDIT_COSTS[operation] * quantity;
  const balance = await getBalance(userId);

  if (balance < cost) {
    return {
      success: false,
      cost,
      newBalance: balance,
      error: `Insufficient credits: need ${cost}, have ${balance}`,
    };
  }

  await db
    .update(subscriptions)
    .set({
      creditBalance: sql`${subscriptions.creditBalance} - ${cost}`,
      updatedAt: new Date(),
    })
    .where(eq(subscriptions.userId, userId));

  await db.insert(creditTransactions).values({
    userId,
    amount: -cost,
    type: "debit",
    source: "usage",
    description: description ?? `${operation} x${quantity}`,
  });

  return { success: true, cost, newBalance: balance - cost };
}

export async function addCredits(params: {
  userId: string;
  amount: number;
  source: "subscription" | "purchase" | "bonus" | "refund";
  sourceId?: string;
  description?: string;
}): Promise<number> {
  const { userId, amount, source, sourceId, description } = params;

  await db
    .update(subscriptions)
    .set({
      creditBalance: sql`${subscriptions.creditBalance} + ${amount}`,
      updatedAt: new Date(),
    })
    .where(eq(subscriptions.userId, userId));

  await db.insert(creditTransactions).values({
    userId,
    amount,
    type: "credit",
    source,
    sourceId,
    description: description ?? `Added ${amount} credits (${source})`,
  });

  return getBalance(userId);
}

export async function resetMonthlyCredits(
  userId: string,
  plan: string,
  monthlyCredits: number
): Promise<void> {
  await db
    .update(subscriptions)
    .set({
      creditBalance: monthlyCredits,
      updatedAt: new Date(),
    })
    .where(eq(subscriptions.userId, userId));

  await db.insert(creditTransactions).values({
    userId,
    amount: monthlyCredits,
    type: "credit",
    source: "subscription",
    description: `Monthly ${plan} credits reset`,
  });
}

export async function getCreditHistory(userId: string, limit = 50) {
  return db
    .select()
    .from(creditTransactions)
    .where(eq(creditTransactions.userId, userId))
    .orderBy(sql`${creditTransactions.createdAt} DESC`)
    .limit(limit);
}
```

### Step 7: Create `app/api/stripe/webhook/route.ts`

```typescript
import { NextResponse } from "next/server";
import { headers } from "next/headers";
import { stripe } from "@/lib/payments/stripe";
import { db } from "@/db";
import { subscriptions } from "@/db/schema";
import { eq } from "drizzle-orm";
import { addCredits, resetMonthlyCredits } from "@/lib/payments/credits";
import { PLANS } from "@/lib/payments/plans";
import type Stripe from "stripe";

export async function POST(request: Request) {
  const body = await request.text();
  const headersList = await headers();
  const signature = headersList.get("stripe-signature");

  if (!signature) {
    return NextResponse.json({ error: "No signature" }, { status: 400 });
  }

  let event: Stripe.Event;

  try {
    event = stripe.webhooks.constructEvent(
      body,
      signature,
      process.env.STRIPE_WEBHOOK_SECRET ?? ""
    );
  } catch {
    return NextResponse.json({ error: "Invalid signature" }, { status: 400 });
  }

  try {
    switch (event.type) {
      case "checkout.session.completed":
        await handleCheckoutComplete(event.data.object as Stripe.Checkout.Session);
        break;

      case "customer.subscription.created":
      case "customer.subscription.updated":
        await handleSubscriptionChange(event.data.object as Stripe.Subscription);
        break;

      case "customer.subscription.deleted":
        await handleSubscriptionCanceled(event.data.object as Stripe.Subscription);
        break;

      case "invoice.paid":
        await handleInvoicePaid(event.data.object as Stripe.Invoice);
        break;
    }

    return NextResponse.json({ received: true });
  } catch (error) {
    console.error("Webhook handler error:", error);
    return NextResponse.json({ error: "Handler failed" }, { status: 500 });
  }
}

async function handleCheckoutComplete(session: Stripe.Checkout.Session) {
  const userId = session.metadata?.userId;
  if (!userId) return;

  // Handle credit pack purchases
  if (session.mode === "payment" && session.metadata?.type === "credits") {
    const creditAmount = parseInt(session.metadata.credits ?? "0", 10);
    if (creditAmount > 0) {
      await addCredits({
        userId,
        amount: creditAmount,
        source: "purchase",
        sourceId: session.id,
      });
    }
  }
}

async function handleSubscriptionChange(subscription: Stripe.Subscription) {
  const customerId = subscription.customer as string;
  const customer = await stripe.customers.retrieve(customerId);

  if (customer.deleted) return;

  const userId = customer.metadata?.userId;
  if (!userId) return;

  const firstItem = subscription.items.data[0];
  const product = firstItem?.price.product as Stripe.Product;
  const plan = (product.metadata?.plan ?? "free") as keyof typeof PLANS;
  const planConfig = PLANS[plan];

  const periodStart = firstItem ? new Date(firstItem.current_period_start * 1000) : null;
  const periodEnd = firstItem ? new Date(firstItem.current_period_end * 1000) : null;

  await db
    .insert(subscriptions)
    .values({
      userId,
      stripeCustomerId: customerId,
      stripeSubscriptionId: subscription.id,
      stripePriceId: firstItem?.price.id,
      plan,
      status: subscription.status === "active" ? "active" : "past_due",
      creditBalance: planConfig?.monthlyCredits ?? 0,
      currentPeriodStart: periodStart,
      currentPeriodEnd: periodEnd,
      cancelAtPeriodEnd: subscription.cancel_at_period_end,
    })
    .onConflictDoUpdate({
      target: subscriptions.userId,
      set: {
        stripeSubscriptionId: subscription.id,
        stripePriceId: firstItem?.price.id,
        plan,
        status: subscription.status === "active" ? "active" : "past_due",
        currentPeriodStart: periodStart,
        currentPeriodEnd: periodEnd,
        cancelAtPeriodEnd: subscription.cancel_at_period_end,
        updatedAt: new Date(),
      },
    });

  if (subscription.status === "active" && planConfig) {
    await resetMonthlyCredits(userId, plan, planConfig.monthlyCredits);
  }
}

async function handleSubscriptionCanceled(subscription: Stripe.Subscription) {
  await db
    .update(subscriptions)
    .set({
      status: "canceled",
      plan: "free",
      updatedAt: new Date(),
    })
    .where(eq(subscriptions.stripeSubscriptionId, subscription.id));
}

async function handleInvoicePaid(invoice: Stripe.Invoice) {
  if (!invoice.parent?.subscription_details?.subscription) return;

  const customerId = typeof invoice.customer === "string"
    ? invoice.customer
    : invoice.customer?.id;
  if (!customerId) return;

  const customer = await stripe.customers.retrieve(customerId);
  if (customer.deleted) return;

  const userId = customer.metadata?.userId;
  if (!userId) return;

  // Subscription renewal — reset credits
  const [sub] = await db
    .select()
    .from(subscriptions)
    .where(eq(subscriptions.userId, userId))
    .limit(1);

  if (sub) {
    const planConfig = PLANS[sub.plan as keyof typeof PLANS];
    if (planConfig) {
      await resetMonthlyCredits(userId, sub.plan, planConfig.monthlyCredits);
    }
  }
}
```

### Step 8: Create `app/api/billing/route.ts`

```typescript
import { NextResponse } from "next/server";
import { db } from "@/db";
import { subscriptions } from "@/db/schema";
import { eq } from "drizzle-orm";
import { auth } from "@/lib/auth";
import { headers } from "next/headers";
import { getCreditHistory } from "@/lib/payments/credits";

export async function GET() {
  const session = await auth.api.getSession({
    headers: await headers(),
  });
  if (!session?.user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const [sub] = await db
    .select()
    .from(subscriptions)
    .where(eq(subscriptions.userId, session.user.id))
    .limit(1);

  const history = await getCreditHistory(session.user.id, 20);

  return NextResponse.json({
    subscription: sub ?? null,
    creditBalance: sub?.creditBalance ?? 0,
    plan: sub?.plan ?? "free",
    history,
  });
}
```

### Step 9: Create `app/api/billing/checkout/route.ts`

```typescript
import { NextResponse } from "next/server";
import { z } from "zod";
import { stripe, getOrCreateCustomer } from "@/lib/payments/stripe";
import { auth } from "@/lib/auth";
import { headers } from "next/headers";

const checkoutSchema = z.object({
  priceId: z.string(),
  mode: z.enum(["subscription", "payment"]).default("subscription"),
  type: z.string().optional(),
  credits: z.string().optional(),
});

export async function POST(request: Request) {
  const session = await auth.api.getSession({
    headers: await headers(),
  });
  if (!session?.user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const body = await request.json();
  const { priceId, mode, type, credits } = checkoutSchema.parse(body);

  const customer = await getOrCreateCustomer({
    userId: session.user.id,
    email: session.user.email,
    name: session.user.name ?? undefined,
  });

  const appUrl = process.env.NEXT_PUBLIC_APP_URL ?? "http://localhost:3000";

  const checkoutSession = await stripe.checkout.sessions.create({
    customer: customer.id,
    mode,
    line_items: [{ price: priceId, quantity: 1 }],
    success_url: `${appUrl}/billing?success=true`,
    cancel_url: `${appUrl}/billing?canceled=true`,
    metadata: {
      userId: session.user.id,
      type: type ?? mode,
      ...(credits ? { credits } : {}),
    },
    ...(mode === "subscription" && {
      subscription_data: {
        metadata: { userId: session.user.id },
      },
    }),
  });

  return NextResponse.json({ url: checkoutSession.url });
}
```

### Step 10: Create `app/api/billing/portal/route.ts`

```typescript
import { NextResponse } from "next/server";
import { stripe } from "@/lib/payments/stripe";
import { db } from "@/db";
import { subscriptions } from "@/db/schema";
import { eq } from "drizzle-orm";
import { auth } from "@/lib/auth";
import { headers } from "next/headers";

export async function POST() {
  const session = await auth.api.getSession({
    headers: await headers(),
  });
  if (!session?.user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const [sub] = await db
    .select({ stripeCustomerId: subscriptions.stripeCustomerId })
    .from(subscriptions)
    .where(eq(subscriptions.userId, session.user.id))
    .limit(1);

  if (!sub?.stripeCustomerId) {
    return NextResponse.json({ error: "No subscription found" }, { status: 404 });
  }

  const appUrl = process.env.NEXT_PUBLIC_APP_URL ?? "http://localhost:3000";

  const portalSession = await stripe.billingPortal.sessions.create({
    customer: sub.stripeCustomerId,
    return_url: `${appUrl}/billing`,
  });

  return NextResponse.json({ url: portalSession.url });
}
```

### Step 11: Create `lib/payments/client.ts`

```typescript
"use client";

import { loadStripe } from "@stripe/stripe-js";

let stripePromise: ReturnType<typeof loadStripe> | null = null;

export function getStripe() {
  if (!stripePromise) {
    stripePromise = loadStripe(process.env.NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY ?? "");
  }
  return stripePromise;
}

export async function redirectToCheckout(
  priceId: string,
  options?: {
    mode?: "subscription" | "payment";
    type?: string;
    credits?: string;
  }
) {
  const response = await fetch("/api/billing/checkout", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ priceId, ...options }),
  });

  const data = await response.json();

  if (data.error) {
    throw new Error(data.error);
  }

  window.location.href = data.url;
}

export async function openBillingPortal() {
  const response = await fetch("/api/billing/portal", {
    method: "POST",
  });

  const data = await response.json();

  if (data.error) {
    throw new Error(data.error);
  }

  window.location.href = data.url;
}
```

### Step 12: Create `components/billing/credit-balance.tsx`

```typescript
"use client";

import { useEffect, useState } from "react";
import { Coins } from "@phosphor-icons/react";

export function CreditBalance() {
  const [balance, setBalance] = useState<number | null>(null);

  useEffect(() => {
    fetch("/api/billing")
      .then((res) => res.json())
      .then((data) => setBalance(data.creditBalance))
      .catch(() => setBalance(0));
  }, []);

  return (
    <div className="flex items-center gap-1.5 rounded-full bg-muted px-3 py-1 text-sm">
      <Coins className="h-3.5 w-3.5 text-amber-500" />
      {balance === null ? (
        <span className="h-4 w-10 animate-pulse rounded bg-muted-foreground/20" />
      ) : (
        <>
          <span className="font-medium">{balance.toLocaleString()}</span>
          <span className="text-muted-foreground">credits</span>
        </>
      )}
    </div>
  );
}
```

### Step 13: Create `components/billing/plan-selector.tsx`

```typescript
"use client";

import { useState, useCallback } from "react";
import { Button } from "@/components/ui/button";
import { Check, CircleNotch } from "@phosphor-icons/react";
import { PLANS } from "@/lib/payments/plans";
import type { PlanName } from "@/lib/payments/plans";
import { redirectToCheckout } from "@/lib/payments/client";

type PlanSelectorProps = {
  currentPlan: PlanName;
  priceIds: Record<PlanName, string>;
};

export function PlanSelector({ currentPlan, priceIds }: PlanSelectorProps) {
  const [loading, setLoading] = useState<PlanName | null>(null);

  const handleSelect = useCallback(async (plan: PlanName) => {
    if (plan === currentPlan || plan === "free") return;
    setLoading(plan);
    try {
      await redirectToCheckout(priceIds[plan], { mode: "subscription" });
    } catch {
      setLoading(null);
    }
  }, [currentPlan, priceIds]);

  return (
    <div className="grid gap-6 md:grid-cols-3">
      {(Object.entries(PLANS) as [PlanName, (typeof PLANS)[PlanName]][]).map(
        ([key, plan]) => (
          <div
            key={key}
            className={`rounded-lg border p-6 ${
              key === currentPlan ? "border-primary ring-2 ring-primary/20" : ""
            }`}
          >
            <h3 className="text-lg font-semibold">{plan.name}</h3>
            <p className="mt-1 text-sm text-muted-foreground">{plan.description}</p>
            <div className="mt-4">
              <span className="text-3xl font-bold">${plan.priceMonthly}</span>
              <span className="text-muted-foreground">/month</span>
            </div>
            <ul className="mt-6 space-y-2">
              {plan.features.map((feature) => (
                <li key={feature} className="flex items-center gap-2 text-sm">
                  <Check className="h-4 w-4 text-green-500" />
                  {feature}
                </li>
              ))}
            </ul>
            <Button
              className="mt-6 w-full"
              variant={key === currentPlan ? "outline" : "default"}
              disabled={key === currentPlan || loading !== null}
              onClick={() => handleSelect(key)}
            >
              {loading === key && <CircleNotch className="mr-2 h-4 w-4 animate-spin" />}
              {key === currentPlan ? "Current Plan" : `Upgrade to ${plan.name}`}
            </Button>
          </div>
        )
      )}
    </div>
  );
}
```

### Step 14: Create `components/billing/upgrade-dialog.tsx`

```typescript
"use client";

import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Lightning } from "@phosphor-icons/react";

type UpgradeDialogProps = {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  requiredCredits: number;
  currentBalance: number;
  onUpgrade: () => void;
};

export function UpgradeDialog({
  open,
  onOpenChange,
  requiredCredits,
  currentBalance,
  onUpgrade,
}: UpgradeDialogProps) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Lightning className="h-5 w-5 text-amber-500" />
            Insufficient Credits
          </DialogTitle>
          <DialogDescription>
            This action requires {requiredCredits} credits, but you only have{" "}
            {currentBalance}. Upgrade your plan or purchase credits to continue.
          </DialogDescription>
        </DialogHeader>
        <div className="flex gap-3 pt-4">
          <Button variant="outline" onClick={() => onOpenChange(false)} className="flex-1">
            Cancel
          </Button>
          <Button onClick={onUpgrade} className="flex-1">
            Upgrade Plan
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}
```

### Step 15: Push database schema

```bash
bunx drizzle-kit push
```

## Usage

### Check balance before an operation

```typescript
import { hasCredits, deductCredits } from "@/lib/payments/credits";

// In an API route
const canProceed = await hasCredits(userId, "image-generation");
if (!canProceed) {
  return NextResponse.json({ error: "Insufficient credits" }, { status: 402 });
}

const result = await deductCredits({
  userId,
  operation: "image-generation",
  description: "Generated image: sunset landscape",
});
```

### Client-side checkout

```typescript
import { redirectToCheckout, openBillingPortal } from "@/lib/payments/client";

// Subscribe to Pro
await redirectToCheckout("price_xxx", { mode: "subscription" });

// Buy 100 credits
await redirectToCheckout("price_xxx", {
  mode: "payment",
  type: "credits",
  credits: "100",
});

// Open billing portal
await openBillingPortal();
```

### Add CreditBalance to header

```tsx
import { CreditBalance } from "@/components/billing/credit-balance";

export function Header() {
  return (
    <header className="flex items-center justify-between p-4">
      <h1>My App</h1>
      <CreditBalance />
    </header>
  );
}
```

## Testing

Test cards:

| Card Number | Result |
|-------------|--------|
| 4242424242424242 | Succeeds |
| 4000000000000002 | Declined |
| 4000002500003155 | 3D Secure required |

Start webhook forwarding:

```bash
docker compose --profile dev up stripe-cli
```

## Acceptance Criteria

- POST `/api/billing/checkout` creates a Stripe checkout session and returns URL
- Webhook handles `checkout.session.completed`, `customer.subscription.created/updated/deleted`, `invoice.paid`
- Credit balance updates on subscription creation/renewal
- `deductCredits()` correctly deducts and returns new balance
- `hasCredits()` returns false when balance is insufficient
- GET `/api/billing` returns subscription info and credit balance
- POST `/api/billing/portal` creates a Stripe billing portal session
- PlanSelector component renders plan cards with upgrade buttons
- CreditBalance badge shows current balance
- `tsc` passes with no errors
- Build succeeds
