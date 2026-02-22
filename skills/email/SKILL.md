---
name: email
description: Setup transactional email with Resend (production) and Mailpit (local) for auth and notifications. Use this skill when the user says "setup email", "add email", "transactional email", or "auth emails".
author: "@mattwoodco"
version: 2.0.2
created: 2026-01-11
updated: 2026-02-13
dependencies: [docker]
---

# Email Setup with Resend + Mailpit

Minimal transactional email system using Resend for production and Mailpit for local development, optimized for auth flows and notifications.

## What Gets Created

### Core Files

1. **`lib/email.ts`** (or `src/lib/email.ts`) - Unified email client (auto-switches between Mailpit/Resend)
2. **`emails/base-layout.tsx`** - Shared layout wrapper
3. **`emails/auth-code.tsx`** - 2FA verification codes
4. **`emails/magic-link.tsx`** - Passwordless login
5. **`emails/password-reset.tsx`** - Password reset flow
6. **`emails/notification.tsx`** - Generic notifications

> **Note**: File paths shown use root-level directories (`lib/`, `emails/`). If your project uses the `src/` directory structure, add `src/` prefix to all paths (e.g., `src/lib/email.ts`).

## Prerequisites

- Next.js project (supports both `src/` and `--no-src-dir` structures)
- Docker stack running (for Mailpit)

## Installation

```bash
bun add resend react-email @react-email/components
```

## Setup Steps

### 1. Update tsconfig.json

Ensure your `tsconfig.json` has proper path mapping:

**For projects with `src/` directory:**
```json
{
  "compilerOptions": {
    "paths": {
      "@/*": ["./src/*"]
    }
  }
}
```

**For projects without `src/` directory (`--no-src-dir`):**
```json
{
  "compilerOptions": {
    "paths": {
      "@/*": ["./*"]
    }
  }
}
```

### 2. Add Environment Variables

Add to `.env.local`:

```env
# Email sender
EMAIL_FROM=noreply@example.com

# Production (Resend)
RESEND_API_KEY=re_...

# Local (Mailpit - already in docker stack)
SMTP_HOST=localhost
SMTP_PORT=1025
```

### 3. Create Email Client

Create `lib/email.ts` (or `src/lib/email.ts` if using `src/` directory):

```typescript
import { Resend } from "resend";
import { render } from "@react-email/components";
import type { ReactElement } from "react";

const isProduction = process.env.NODE_ENV === "production";
const resend = process.env.RESEND_API_KEY ? new Resend(process.env.RESEND_API_KEY) : null;

type SendEmailOptions = {
  to: string | string[];
  subject: string;
  template: ReactElement;
  replyTo?: string;
};

export async function sendEmail(options: SendEmailOptions) {
  const html = await render(options.template);
  const text = await render(options.template, { plainText: true });
  const from = process.env.EMAIL_FROM ?? "noreply@example.com";

  if (isProduction && resend) {
    return resend.emails.send({
      from,
      to: Array.isArray(options.to) ? options.to : [options.to],
      subject: options.subject,
      html,
      text,
      replyTo: options.replyTo,
    });
  }

  // Local: use Mailpit via nodemailer
  const nodemailer = await import("nodemailer");
  const transport = nodemailer.createTransport({
    host: process.env.SMTP_HOST || "localhost",
    port: Number(process.env.SMTP_PORT) || 1025,
    secure: false,
  });

  return transport.sendMail({
    from,
    to: options.to,
    subject: options.subject,
    html,
    text,
  });
}
```

### 4. Create Base Layout

Create `emails/base-layout.tsx` (or `src/emails/base-layout.tsx` if using `src/` directory):

```tsx
import {
  Body,
  Container,
  Head,
  Html,
  Preview,
  Tailwind,
} from "@react-email/components";
import type { ReactNode } from "react";

type Props = { preview: string; children: ReactNode };

export function BaseLayout({ preview, children }: Props) {
  return (
    <Html>
      <Head />
      <Preview>{preview}</Preview>
      <Tailwind>
        <Body className="bg-zinc-50 font-sans">
          <Container className="mx-auto max-w-[600px] p-8">
            {children}
          </Container>
        </Body>
      </Tailwind>
    </Html>
  );
}
```

### 5. Create Auth Templates

Create `emails/auth-code.tsx` (or `src/emails/auth-code.tsx` if using `src/` directory):

```tsx
import { Heading, Section, Text } from "@react-email/components";
import { BaseLayout } from "./base-layout";

type Props = { code: string; expiresIn?: string };

export function AuthCodeEmail({ code, expiresIn = "10 minutes" }: Props) {
  return (
    <BaseLayout preview={`Your verification code: ${code}`}>
      <Heading className="text-2xl font-bold text-zinc-900">
        Verification Code
      </Heading>
      <Section className="my-6 rounded-lg bg-zinc-100 p-6 text-center">
        <Text className="m-0 font-mono text-4xl font-bold tracking-widest text-zinc-900">
          {code}
        </Text>
      </Section>
      <Text className="text-zinc-600">
        This code expires in {expiresIn}. If you didn't request this, ignore this email.
      </Text>
    </BaseLayout>
  );
}
```

Create `emails/magic-link.tsx`:

```tsx
import { Button, Heading, Text } from "@react-email/components";
import { BaseLayout } from "./base-layout";

type Props = { url: string; expiresIn?: string };

export function MagicLinkEmail({ url, expiresIn = "15 minutes" }: Props) {
  return (
    <BaseLayout preview="Sign in to your account">
      <Heading className="text-2xl font-bold text-zinc-900">
        Sign In
      </Heading>
      <Text className="text-zinc-600">
        Click the button below to sign in. This link expires in {expiresIn}.
      </Text>
      <Button
        href={url}
        className="rounded-lg bg-zinc-900 px-6 py-3 text-white"
      >
        Sign In
      </Button>
      <Text className="mt-4 text-sm text-zinc-500">
        If the button doesn't work, copy this link: {url}
      </Text>
    </BaseLayout>
  );
}
```

Create `emails/password-reset.tsx`:

```tsx
import { Button, Heading, Text } from "@react-email/components";
import { BaseLayout } from "./base-layout";

type Props = { url: string; expiresIn?: string };

export function PasswordResetEmail({ url, expiresIn = "1 hour" }: Props) {
  return (
    <BaseLayout preview="Reset your password">
      <Heading className="text-2xl font-bold text-zinc-900">
        Reset Password
      </Heading>
      <Text className="text-zinc-600">
        Someone requested a password reset. If this was you, click below.
        This link expires in {expiresIn}.
      </Text>
      <Button
        href={url}
        className="rounded-lg bg-zinc-900 px-6 py-3 text-white"
      >
        Reset Password
      </Button>
      <Text className="mt-4 text-sm text-zinc-500">
        If you didn't request this, ignore this email.
      </Text>
    </BaseLayout>
  );
}
```

Create `emails/notification.tsx`:

```tsx
import { Button, Heading, Text } from "@react-email/components";
import { BaseLayout } from "./base-layout";

type Props = {
  title: string;
  message: string;
  actionUrl?: string;
  actionText?: string;
};

export function NotificationEmail({ title, message, actionUrl, actionText }: Props) {
  return (
    <BaseLayout preview={title}>
      <Heading className="text-2xl font-bold text-zinc-900">{title}</Heading>
      <Text className="text-zinc-600">{message}</Text>
      {actionUrl && (
        <Button
          href={actionUrl}
          className="rounded-lg bg-zinc-900 px-6 py-3 text-white"
        >
          {actionText ?? "View"}
        </Button>
      )}
    </BaseLayout>
  );
}
```

## Usage Examples

### Send Auth Code

```typescript
import { sendEmail } from "@/lib/email";
import { AuthCodeEmail } from "@/emails/auth-code";

await sendEmail({
  to: "user@example.com",
  subject: "Your verification code",
  template: <AuthCodeEmail code="123456" />,
});
```

### Send Magic Link

```typescript
import { MagicLinkEmail } from "@/emails/magic-link";

await sendEmail({
  to: "user@example.com",
  subject: "Sign in to your account",
  template: <MagicLinkEmail url="https://app.com/auth/verify?token=xyz" />,
});
```

### Send Password Reset

```typescript
import { PasswordResetEmail } from "@/emails/password-reset";

await sendEmail({
  to: "user@example.com",
  subject: "Reset your password",
  template: <PasswordResetEmail url="https://app.com/reset?token=xyz" />,
});
```

### Send Generic Notification

```typescript
import { NotificationEmail } from "@/emails/notification";

await sendEmail({
  to: "user@example.com",
  subject: "Welcome!",
  template: (
    <NotificationEmail
      title="Welcome to our platform"
      message="Thanks for signing up!"
      actionUrl="https://app.com/dashboard"
      actionText="Go to Dashboard"
    />
  ),
});
```

## Local Development

1. Start Docker stack (includes Mailpit):
   ```bash
   docker compose up -d
   ```

2. View sent emails at: http://localhost:8025

3. All emails sent locally go to Mailpit regardless of recipient

## Testing Templates

Preview all templates in browser:

```bash
bunx email dev
```

Opens React Email preview at http://localhost:3000

## Integration with Auth

This email setup is ready for auth integration:

- **better-auth**: Use in `sendResetPassword` and `sendVerificationEmail` callbacks
- **NextAuth**: Use in custom email provider
- **Clerk**: Use for custom email notifications
- **Custom auth**: Direct integration via `sendEmail` function

## Production Setup

1. Sign up for [Resend](https://resend.com)
2. Verify your domain
3. Get API key (starts with `re_`)
4. Add to production environment variables:
   ```env
   RESEND_API_KEY=re_your_key_here
   EMAIL_FROM=noreply@yourdomain.com
   ```

## Extending

To add more templates later:

1. Create new file in `emails/` (or `src/emails/`)
2. Use `BaseLayout` wrapper
3. Follow existing template patterns
4. Import and use in your code

**Common additions:**
- Welcome email
- Email verification
- Account deletion confirmation
- Payment receipts
- Weekly digests

## Troubleshooting

### Emails not sending to Mailpit

1. **Check Mailpit is running:**
   ```bash
   docker ps | grep mailpit
   ```

2. **Verify SMTP port:** Check your Mailpit container ports. Some configurations use different ports:
   ```bash
   docker ps --format "{{.Names}}\t{{.Ports}}" | grep mailpit
   ```

   Common port mappings:
   - Default: `1025:1025` (SMTP) and `8025:8025` (Web UI)
   - Alternative: `1026:1025` (SMTP) and `8026:8025` (Web UI)

   Update your `.env.local` to match your actual ports:
   ```env
   SMTP_PORT=1026  # Use your actual SMTP port
   ```

3. **Check EMAIL_FROM is set:** Ensure `.env.local` includes:
   ```env
   EMAIL_FROM=noreply@example.com
   ```

4. **View Mailpit UI:** Open your browser to the correct port:
   - Default: http://localhost:8025
   - Alternative: http://localhost:8026

### TypeScript errors in email templates

If you see import errors, ensure your `tsconfig.json` paths match your project structure (`@/*` should point to `./src/*` or `./*`).

### React Email preview not loading

The preview server may conflict with your Next.js dev server. Use a different port:
```bash
bunx email dev --port 3001
```
