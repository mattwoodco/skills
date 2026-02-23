---
name: observability
description: Setup OpenTelemetry tracing and structured logging for Next.js applications. Use this skill when the user says "setup observability", "add tracing", "setup logging", "add telemetry", or "instrument app".
author: "@mattwoodco"
version: 1.1.0
created: 2026-01-11
updated: 2026-02-17
validated: 2026-02-17
dependencies: [docker, env-config]
---

# Observability Setup

Creates a complete observability stack with OpenTelemetry tracing and structured logging for Next.js applications. Supports multiple backends including Vercel, Baselime, Axiom, and HyperDX.

## What Gets Created

### `src/instrumentation.ts`

- Next.js instrumentation file for automatic tracing
- OpenTelemetry SDK initialization
- Automatic instrumentation for fetch, HTTP, and Node.js
- Environment-aware configuration (dev vs production)

### `src/lib/observability.ts`

- Structured logging utilities with trace context
- Custom span creation helpers
- Request/response logging middleware
- Error tracking with stack traces
- Performance measurement utilities

## Installation

```bash
bun add @opentelemetry/api @opentelemetry/sdk-node @opentelemetry/auto-instrumentations-node @opentelemetry/exporter-trace-otlp-http @opentelemetry/resources @opentelemetry/semantic-conventions @opentelemetry/sdk-trace-node
```

For Vercel-specific setup:

```bash
bun add @vercel/otel
```

## Environment Variables

Add to your `.env.local`:

```env
# OpenTelemetry Configuration
OTEL_SERVICE_NAME=my-app
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
OTEL_EXPORTER_OTLP_HEADERS=

# For Baselime
# OTEL_EXPORTER_OTLP_ENDPOINT=https://otel.baselime.io/v1
# OTEL_EXPORTER_OTLP_HEADERS=x-api-key=your-baselime-api-key

# For Axiom
# OTEL_EXPORTER_OTLP_ENDPOINT=https://api.axiom.co/v1/traces
# OTEL_EXPORTER_OTLP_HEADERS=Authorization=Bearer your-axiom-token,X-Axiom-Dataset=your-dataset

# For HyperDX
# OTEL_EXPORTER_OTLP_ENDPOINT=https://in-otel.hyperdx.io
# OTEL_EXPORTER_OTLP_HEADERS=authorization=your-hyperdx-api-key

# Log Level (debug, info, warn, error)
LOG_LEVEL=info
```

Add to `src/env.ts`:

```typescript
server: {
  OTEL_SERVICE_NAME: z.string().default("my-app"),
  OTEL_EXPORTER_OTLP_ENDPOINT: z.string().url().optional(),
  OTEL_EXPORTER_OTLP_HEADERS: z.string().optional(),
  LOG_LEVEL: z.enum(["debug", "info", "warn", "error"]).default("info"),
}
```

## Quick Setup

### 1. Create Instrumentation File (`src/instrumentation.ts`)

```typescript
import { NodeSDK } from "@opentelemetry/sdk-node";
import { OTLPTraceExporter } from "@opentelemetry/exporter-trace-otlp-http";
import { getNodeAutoInstrumentations } from "@opentelemetry/auto-instrumentations-node";
import { resourceFromAttributes } from "@opentelemetry/resources";
import { ATTR_SERVICE_NAME, ATTR_SERVICE_VERSION } from "@opentelemetry/semantic-conventions";
import { BatchSpanProcessor } from "@opentelemetry/sdk-trace-node";

export async function register() {
  if (process.env.NEXT_RUNTIME === "nodejs") {
    const resource = resourceFromAttributes({
      [ATTR_SERVICE_NAME]: process.env.OTEL_SERVICE_NAME ?? "my-app",
      [ATTR_SERVICE_VERSION]: process.env.npm_package_version ?? "0.0.0",
      environment: process.env.NODE_ENV ?? "development",
    });

    const traceExporter = new OTLPTraceExporter({
      url: process.env.OTEL_EXPORTER_OTLP_ENDPOINT
        ? `${process.env.OTEL_EXPORTER_OTLP_ENDPOINT}/v1/traces`
        : undefined,
      headers: parseOtelHeaders(process.env.OTEL_EXPORTER_OTLP_HEADERS),
    });

    const sdk = new NodeSDK({
      resource,
      spanProcessor: new BatchSpanProcessor(traceExporter),
      instrumentations: [
        getNodeAutoInstrumentations({
          "@opentelemetry/instrumentation-fs": { enabled: false },
          "@opentelemetry/instrumentation-http": {
            ignoreIncomingRequestHook: (request) => {
              // Ignore health checks and static assets
              const url = request.url ?? "";
              return (
                url.includes("/_next/") ||
                url.includes("/favicon") ||
                url === "/health" ||
                url === "/ready"
              );
            },
          },
          "@opentelemetry/instrumentation-undici": {
            enabled: false, // Avoid tracing the OTEL exporter's own requests
          },
        }),
      ],
    });

    sdk.start();

    process.on("SIGTERM", () => {
      sdk.shutdown().catch(console.error);
    });
  }
}

function parseOtelHeaders(
  headers: string | undefined
): Record<string, string> | undefined {
  if (!headers) return undefined;
  return Object.fromEntries(
    headers.split(",").map((h) => {
      const [key, ...values] = h.split("=");
      return [key.trim(), values.join("=").trim()];
    })
  );
}
```

### 2. Create Observability Utilities (`src/lib/observability.ts`)

```typescript
import { trace, context, SpanStatusCode, type Span } from "@opentelemetry/api";

const tracer = trace.getTracer("app");

type LogLevel = "debug" | "info" | "warn" | "error";

type LogContext = Record<string, unknown>;

const LOG_LEVELS: Record<LogLevel, number> = {
  debug: 0,
  info: 1,
  warn: 2,
  error: 3,
};

function getLogLevel(): number {
  const level = (process.env.LOG_LEVEL ?? "info") as LogLevel;
  return LOG_LEVELS[level] ?? LOG_LEVELS.info;
}

function shouldLog(level: LogLevel): boolean {
  return LOG_LEVELS[level] >= getLogLevel();
}

function getTraceContext(): LogContext {
  const span = trace.getActiveSpan();
  if (!span) return {};

  const spanContext = span.spanContext();
  return {
    traceId: spanContext.traceId,
    spanId: spanContext.spanId,
  };
}

function formatLog(
  level: LogLevel,
  message: string,
  ctx: LogContext = {}
): string {
  const timestamp = new Date().toISOString();
  const traceCtx = getTraceContext();

  const logEntry = {
    timestamp,
    level,
    message,
    ...traceCtx,
    ...ctx,
  };

  return JSON.stringify(logEntry);
}

export const logger = {
  debug(message: string, ctx?: LogContext) {
    if (shouldLog("debug")) {
      console.debug(formatLog("debug", message, ctx));
    }
  },

  info(message: string, ctx?: LogContext) {
    if (shouldLog("info")) {
      console.info(formatLog("info", message, ctx));
    }
  },

  warn(message: string, ctx?: LogContext) {
    if (shouldLog("warn")) {
      console.warn(formatLog("warn", message, ctx));
    }
  },

  error(message: string, error?: Error, ctx?: LogContext) {
    if (shouldLog("error")) {
      const errorCtx = error
        ? {
            error: {
              name: error.name,
              message: error.message,
              stack: error.stack,
            },
          }
        : {};
      console.error(formatLog("error", message, { ...errorCtx, ...ctx }));
    }

    // Also record error in active span
    const span = trace.getActiveSpan();
    if (span && error) {
      span.recordException(error);
      span.setStatus({ code: SpanStatusCode.ERROR, message: error.message });
    }
  },
};

export function withSpan<T>(
  name: string,
  fn: (span: Span) => Promise<T>,
  attributes?: Record<string, string | number | boolean>
): Promise<T> {
  return tracer.startActiveSpan(name, async (span) => {
    if (attributes) {
      span.setAttributes(attributes);
    }

    try {
      const result = await fn(span);
      span.setStatus({ code: SpanStatusCode.OK });
      return result;
    } catch (error) {
      if (error instanceof Error) {
        span.recordException(error);
        span.setStatus({ code: SpanStatusCode.ERROR, message: error.message });
      }
      throw error;
    } finally {
      span.end();
    }
  });
}

export function withSpanSync<T>(
  name: string,
  fn: (span: Span) => T,
  attributes?: Record<string, string | number | boolean>
): T {
  const span = tracer.startSpan(name);

  if (attributes) {
    span.setAttributes(attributes);
  }

  try {
    const result = context.with(trace.setSpan(context.active(), span), () =>
      fn(span)
    );
    span.setStatus({ code: SpanStatusCode.OK });
    return result;
  } catch (error) {
    if (error instanceof Error) {
      span.recordException(error);
      span.setStatus({ code: SpanStatusCode.ERROR, message: error.message });
    }
    throw error;
  } finally {
    span.end();
  }
}

export function addSpanAttributes(
  attributes: Record<string, string | number | boolean>
) {
  const span = trace.getActiveSpan();
  if (span) {
    span.setAttributes(attributes);
  }
}

export function addSpanEvent(
  name: string,
  attributes?: Record<string, string | number | boolean>
) {
  const span = trace.getActiveSpan();
  if (span) {
    span.addEvent(name, attributes);
  }
}

export function measureAsync<T>(
  name: string,
  fn: () => Promise<T>,
  attributes?: Record<string, string | number | boolean>
): Promise<T> {
  const start = performance.now();

  return withSpan(
    name,
    async (span) => {
      const result = await fn();
      const duration = performance.now() - start;

      span.setAttribute("duration_ms", duration);
      logger.debug(`${name} completed`, { duration_ms: duration });

      return result;
    },
    attributes
  );
}

export function measureSync<T>(
  name: string,
  fn: () => T,
  attributes?: Record<string, string | number | boolean>
): T {
  const start = performance.now();

  return withSpanSync(
    name,
    (span) => {
      const result = fn();
      const duration = performance.now() - start;

      span.setAttribute("duration_ms", duration);
      logger.debug(`${name} completed`, { duration_ms: duration });

      return result;
    },
    attributes
  );
}
```

### 3. Next.js Instrumentation (Automatic)

Next.js 15+ automatically detects `src/instrumentation.ts` — no config changes needed. The `register()` export is called at server startup.

## Usage Examples

### Basic Logging

```typescript
import { logger } from "@src/lib/observability";

// Simple logging with automatic trace context
logger.info("User signed in", { userId: "123", provider: "google" });

logger.error("Failed to process payment", new Error("Card declined"), {
  orderId: "order-456",
  amount: 99.99,
});
```

### Custom Spans

```typescript
import { withSpan, addSpanAttributes } from "@src/lib/observability";

async function processOrder(orderId: string) {
  return withSpan(
    "process-order",
    async (span) => {
      // Add custom attributes
      span.setAttribute("order.id", orderId);

      // Do work...
      const order = await fetchOrder(orderId);

      // Add more context as you go
      addSpanAttributes({
        "order.total": order.total,
        "order.items_count": order.items.length,
      });

      return order;
    },
    { "order.id": orderId }
  );
}
```

### Performance Measurement

```typescript
import { measureAsync } from "@src/lib/observability";

async function generateReport(userId: string) {
  return measureAsync(
    "generate-report",
    async () => {
      // Long-running operation
      const data = await fetchUserData(userId);
      return compileReport(data);
    },
    { "user.id": userId, "report.type": "monthly" }
  );
}
```

### API Route Logging

```typescript
import { NextResponse } from "next/server";
import { logger, withSpan } from "@src/lib/observability";

export async function POST(request: Request) {
  return withSpan("api.create-user", async (span) => {
    try {
      const body = await request.json();

      logger.info("Creating user", { email: body.email });

      const user = await createUser(body);

      span.setAttribute("user.id", user.id);
      logger.info("User created successfully", { userId: user.id });

      return NextResponse.json(user, { status: 201 });
    } catch (error) {
      logger.error("Failed to create user", error as Error);
      return NextResponse.json(
        { error: "Failed to create user" },
        { status: 500 }
      );
    }
  });
}
```

## Vercel Integration

For Vercel deployments, use the official `@vercel/otel` package for optimized tracing:

```typescript
// src/instrumentation.ts
import { registerOTel } from "@vercel/otel";

export function register() {
  registerOTel({
    serviceName: process.env.OTEL_SERVICE_NAME ?? "my-app",
  });
}
```

Enable in Vercel dashboard:

1. Go to Project Settings > Observability
2. Enable OpenTelemetry
3. Connect your preferred backend (Axiom, Baselime, etc.)

## Backend Configuration

### Baselime

```env
OTEL_EXPORTER_OTLP_ENDPOINT=https://otel.baselime.io/v1
OTEL_EXPORTER_OTLP_HEADERS=x-api-key=your-baselime-api-key
```

### Axiom

```env
OTEL_EXPORTER_OTLP_ENDPOINT=https://api.axiom.co/v1/traces
OTEL_EXPORTER_OTLP_HEADERS=Authorization=Bearer your-axiom-token,X-Axiom-Dataset=traces
```

### HyperDX

```env
OTEL_EXPORTER_OTLP_ENDPOINT=https://in-otel.hyperdx.io
OTEL_EXPORTER_OTLP_HEADERS=authorization=your-hyperdx-api-key
```

### Local Development (Jaeger)

Jaeger is included in the Docker Compose stack (see docker skill). Start it with:

```bash
docker compose up -d jaeger
```

The environment variable is already configured in `.env.local`:

```env
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
```

View traces at `http://localhost:16686`

## Best Practices

1. **Use meaningful span names**: `api.create-user` > `createUser`
2. **Add relevant attributes**: User IDs, order IDs, feature flags
3. **Log at appropriate levels**: Debug for development, Info for production events
4. **Include trace context**: All logs automatically include traceId/spanId
5. **Handle errors properly**: Use `logger.error()` with Error objects
6. **Measure critical paths**: Use `measureAsync()` for performance-sensitive code

## Testing

Verify instrumentation is working:

```bash
# Start the app
bun dev

# Check console for structured logs
# Traces should appear in your configured backend

# For local Jaeger
open http://localhost:16686
```

## Next Steps

1. Configure your preferred observability backend
2. Add custom spans to critical code paths
3. Set up alerts based on error rates and latency
4. Create dashboards for key metrics
5. Integrate with error tracking (Sentry, etc.)
