---
name: notifications-push
description: Web Push notifications with VAPID — subscribe devices, send targeted pushes, notification preferences, and in-app notification center. Use this skill when the user says "add push notifications", "setup notifications", "add web push", "notification bell", or "push notifications".
author: "@mattwoodco"
version: 1.0.0
created: 2026-02-18
dependencies: [auth, db, add-pwa]
---

# Push Notifications

Web Push API notifications with VAPID authentication. Includes device subscription management, targeted push delivery, per-user notification preferences, an in-app notification center with bell icon, and a service worker for background push handling.

## Prerequisites

- Next.js app with `src/` directory and App Router
- `auth` skill installed (`withAuth` available at `@/lib/auth-guard`)
- `db` skill installed (Drizzle ORM + Postgres)
- `add-pwa` skill installed (service worker registration support)
- shadcn/ui initialized

## Installation

```bash
bun add web-push
bun add -D @types/web-push
```

## Environment Variables

Add to `.env.local`:

```env
# Web Push (VAPID)
NEXT_PUBLIC_VAPID_PUBLIC_KEY=your-vapid-public-key
VAPID_PRIVATE_KEY=your-vapid-private-key
VAPID_SUBJECT=mailto:you@example.com
```

### Generate VAPID Keys

```bash
bunx web-push generate-vapid-keys
```

Copy the output into your `.env.local` file.

### Update `src/env.ts`

Add to the `server` object:

```typescript
server: {
  // ... existing variables
  VAPID_PRIVATE_KEY: z.string().min(1),
  VAPID_SUBJECT: z.string().startsWith("mailto:"),
},
```

Add to the `client` object:

```typescript
client: {
  // ... existing variables
  NEXT_PUBLIC_VAPID_PUBLIC_KEY: z.string().min(1),
},
```

Add to the `runtimeEnv` object:

```typescript
runtimeEnv: {
  // ... existing variables
  VAPID_PRIVATE_KEY: process.env.VAPID_PRIVATE_KEY,
  VAPID_SUBJECT: process.env.VAPID_SUBJECT,
  NEXT_PUBLIC_VAPID_PUBLIC_KEY: process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY,
},
```

## What Gets Created

```
src/
├── lib/
│   ├── notifications/
│   │   ├── push.ts                            # Server: initWebPush, sendPushNotification, sendBulkNotifications
│   │   ├── types.ts                           # PushSubscription, NotificationPayload, NotificationPreference
│   │   └── use-push.ts                        # Client hook: requestPermission, subscribe, unsubscribe
│   └── db/
│       └── schema/
│           └── push-subscriptions.ts          # push_subscriptions, notification_preferences, notifications tables
├── components/
│   └── notifications/
│       ├── notification-bell.tsx              # Bell icon with unread count badge
│       ├── notification-center.tsx            # Dropdown notification list
│       └── permission-prompt.tsx              # One-time permission request dialog
├── app/
│   └── api/
│       └── notifications/
│           ├── subscribe/
│           │   └── route.ts                   # POST register push subscription
│           ├── preferences/
│           │   └── route.ts                   # GET/PUT notification preferences
│           └── route.ts                       # GET list, PATCH mark as read
└── public/
    └── sw-push.js                             # Service worker for push events
```

## Database

After applying this skill, push the schema:

```bash
bunx drizzle-kit push
```

## Setup Steps

### Step 1: Create `src/lib/notifications/types.ts`

```typescript
export type PushSubscriptionData = {
  endpoint: string;
  keys: {
    p256dh: string;
    auth: string;
  };
};

export type NotificationPayload = {
  title: string;
  body: string;
  icon?: string;
  url?: string;
  actions?: Array<{
    action: string;
    title: string;
  }>;
};

export type NotificationPreference = {
  roomInvites: boolean;
  mentions: boolean;
  callAlerts: boolean;
  meetingSummaries: boolean;
};

export type NotificationRecord = {
  id: string;
  userId: string;
  title: string;
  body: string;
  url: string | null;
  read: boolean;
  createdAt: string;
};
```

### Step 2: Create `src/lib/notifications/push.ts`

```typescript
import webPush from "web-push";
import { db } from "@/lib/db";
import { pushSubscriptions, notifications } from "@/lib/db/schema/push-subscriptions";
import { eq } from "drizzle-orm";
import type { NotificationPayload } from "./types";

let initialized = false;

export function initWebPush() {
  if (initialized) return;

  const publicKey = process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY;
  const privateKey = process.env.VAPID_PRIVATE_KEY;
  const subject = process.env.VAPID_SUBJECT;

  if (!publicKey || !privateKey || !subject) {
    throw new Error(
      "VAPID keys not configured. Set NEXT_PUBLIC_VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY, and VAPID_SUBJECT."
    );
  }

  webPush.setVapidDetails(subject, publicKey, privateKey);
  initialized = true;
}

/**
 * Send a push notification to a specific user.
 * Sends to all subscribed devices for that user.
 * Also stores the notification in the database for the in-app notification center.
 */
export async function sendPushNotification(
  userId: string,
  payload: NotificationPayload
): Promise<{ sent: number; failed: number }> {
  initWebPush();

  // Store in-app notification
  await db.insert(notifications).values({
    userId,
    title: payload.title,
    body: payload.body,
    url: payload.url ?? null,
  });

  // Get all subscriptions for this user
  const subscriptions = await db
    .select()
    .from(pushSubscriptions)
    .where(eq(pushSubscriptions.userId, userId));

  let sent = 0;
  let failed = 0;

  const pushPayload = JSON.stringify({
    title: payload.title,
    body: payload.body,
    icon: payload.icon ?? "/icon-192x192.png",
    url: payload.url ?? "/",
    actions: payload.actions ?? [],
  });

  for (const sub of subscriptions) {
    try {
      await webPush.sendNotification(
        {
          endpoint: sub.endpoint,
          keys: {
            p256dh: sub.p256dh,
            auth: sub.auth,
          },
        },
        pushPayload
      );
      sent++;
    } catch (error) {
      failed++;

      // Remove expired/invalid subscriptions (410 Gone)
      if (
        error instanceof webPush.WebPushError &&
        error.statusCode === 410
      ) {
        await db
          .delete(pushSubscriptions)
          .where(eq(pushSubscriptions.id, sub.id));
      }
    }
  }

  return { sent, failed };
}

/**
 * Send a push notification to multiple users.
 */
export async function sendBulkNotifications(
  userIds: string[],
  payload: NotificationPayload
): Promise<{ totalSent: number; totalFailed: number }> {
  let totalSent = 0;
  let totalFailed = 0;

  const results = await Promise.allSettled(
    userIds.map((userId) => sendPushNotification(userId, payload))
  );

  for (const result of results) {
    if (result.status === "fulfilled") {
      totalSent += result.value.sent;
      totalFailed += result.value.failed;
    } else {
      totalFailed++;
    }
  }

  return { totalSent, totalFailed };
}
```

### Step 3: Create `src/lib/notifications/use-push.ts`

```tsx
"use client";

import { useState, useEffect, useCallback } from "react";

function urlBase64ToUint8Array(base64String: string): Uint8Array<ArrayBuffer> {
  const padding = "=".repeat((4 - (base64String.length % 4)) % 4);
  const base64 = (base64String + padding)
    .replace(/-/g, "+")
    .replace(/_/g, "/");

  const rawData = window.atob(base64);
  const outputArray = new Uint8Array(rawData.length);

  for (let i = 0; i < rawData.length; ++i) {
    outputArray[i] = rawData.charCodeAt(i);
  }

  return outputArray;
}

type UsePushReturn = {
  isSupported: boolean;
  isSubscribed: boolean;
  isLoading: boolean;
  permission: NotificationPermission | "unsupported";
  requestPermission: () => Promise<NotificationPermission>;
  subscribe: () => Promise<void>;
  unsubscribe: () => Promise<void>;
};

export function usePush(): UsePushReturn {
  const [isSupported, setIsSupported] = useState(false);
  const [isSubscribed, setIsSubscribed] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const [permission, setPermission] = useState<NotificationPermission | "unsupported">("unsupported");

  // Check support and current subscription status
  useEffect(() => {
    const checkSupport = async () => {
      const supported =
        typeof window !== "undefined" &&
        "serviceWorker" in navigator &&
        "PushManager" in window &&
        "Notification" in window;

      setIsSupported(supported);

      if (!supported) {
        setIsLoading(false);
        return;
      }

      setPermission(Notification.permission);

      try {
        const registration = await navigator.serviceWorker.ready;
        const subscription = await registration.pushManager.getSubscription();
        setIsSubscribed(subscription !== null);
      } catch {
        setIsSubscribed(false);
      } finally {
        setIsLoading(false);
      }
    };

    void checkSupport();
  }, []);

  const requestPermission = useCallback(async (): Promise<NotificationPermission> => {
    if (!isSupported) return "denied";

    const result = await Notification.requestPermission();
    setPermission(result);
    return result;
  }, [isSupported]);

  const subscribe = useCallback(async () => {
    if (!isSupported) return;

    setIsLoading(true);

    try {
      // Request permission if not already granted
      let currentPermission = Notification.permission;
      if (currentPermission === "default") {
        currentPermission = await Notification.requestPermission();
        setPermission(currentPermission);
      }

      if (currentPermission !== "granted") {
        throw new Error("Notification permission denied");
      }

      // Register service worker if not already registered
      const registration = await navigator.serviceWorker.register("/sw-push.js", {
        scope: "/",
      });

      await navigator.serviceWorker.ready;

      // Subscribe to push notifications
      const vapidPublicKey = process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY;
      if (!vapidPublicKey) {
        throw new Error("VAPID public key not configured");
      }

      const subscription = await registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlBase64ToUint8Array(vapidPublicKey),
      });

      // Send subscription to server
      const keys = subscription.toJSON().keys;
      if (!keys) {
        throw new Error("Subscription keys not available");
      }

      const res = await fetch("/api/notifications/subscribe", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          endpoint: subscription.endpoint,
          p256dh: keys.p256dh,
          auth: keys.auth,
        }),
      });

      if (!res.ok) {
        throw new Error("Failed to register subscription on server");
      }

      setIsSubscribed(true);
    } catch (error) {
      console.error("Push subscription failed:", error);
      throw error;
    } finally {
      setIsLoading(false);
    }
  }, [isSupported]);

  const unsubscribe = useCallback(async () => {
    if (!isSupported) return;

    setIsLoading(true);

    try {
      const registration = await navigator.serviceWorker.ready;
      const subscription = await registration.pushManager.getSubscription();

      if (subscription) {
        await subscription.unsubscribe();

        // Notify server
        await fetch("/api/notifications/subscribe", {
          method: "DELETE",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ endpoint: subscription.endpoint }),
        });
      }

      setIsSubscribed(false);
    } catch (error) {
      console.error("Push unsubscribe failed:", error);
      throw error;
    } finally {
      setIsLoading(false);
    }
  }, [isSupported]);

  return {
    isSupported,
    isSubscribed,
    isLoading,
    permission,
    requestPermission,
    subscribe,
    unsubscribe,
  };
}
```

### Step 4: Create `src/components/notifications/notification-bell.tsx`

```tsx
"use client";

import { useState, useEffect, useCallback } from "react";
import { Button } from "@/components/ui/button";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { Bell } from "lucide-react";
import { NotificationCenter } from "./notification-center";
import type { NotificationRecord } from "@/lib/notifications/types";

export function NotificationBell() {
  const [unreadCount, setUnreadCount] = useState(0);
  const [notifications, setNotifications] = useState<NotificationRecord[]>([]);
  const [isOpen, setIsOpen] = useState(false);
  const [isLoading, setIsLoading] = useState(false);

  const loadNotifications = useCallback(async () => {
    setIsLoading(true);
    try {
      const res = await fetch("/api/notifications?limit=20");
      if (!res.ok) return;
      const data: { notifications: NotificationRecord[]; unreadCount: number } =
        await res.json();
      setNotifications(data.notifications);
      setUnreadCount(data.unreadCount);
    } catch {
      // Silently fail
    } finally {
      setIsLoading(false);
    }
  }, []);

  // Load notifications on mount and periodically
  useEffect(() => {
    void loadNotifications();

    const interval = setInterval(() => {
      void loadNotifications();
    }, 30000); // Poll every 30 seconds

    return () => clearInterval(interval);
  }, [loadNotifications]);

  // Reload when popover opens
  useEffect(() => {
    if (isOpen) {
      void loadNotifications();
    }
  }, [isOpen, loadNotifications]);

  const handleMarkAsRead = useCallback(
    async (notificationId: string) => {
      try {
        const res = await fetch("/api/notifications", {
          method: "PATCH",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ notificationId, read: true }),
        });

        if (res.ok) {
          setNotifications((prev) =>
            prev.map((n) =>
              n.id === notificationId ? { ...n, read: true } : n
            )
          );
          setUnreadCount((prev) => Math.max(0, prev - 1));
        }
      } catch {
        // Silently fail
      }
    },
    []
  );

  const handleMarkAllRead = useCallback(async () => {
    try {
      const res = await fetch("/api/notifications", {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ markAllRead: true }),
      });

      if (res.ok) {
        setNotifications((prev) =>
          prev.map((n) => ({ ...n, read: true }))
        );
        setUnreadCount(0);
      }
    } catch {
      // Silently fail
    }
  }, []);

  return (
    <Popover open={isOpen} onOpenChange={setIsOpen}>
      <PopoverTrigger asChild>
        <Button variant="ghost" size="icon" className="relative">
          <Bell className="h-5 w-5" />
          {unreadCount > 0 && (
            <span className="absolute -right-0.5 -top-0.5 flex h-4 min-w-4 items-center justify-center rounded-full bg-destructive px-1 text-[10px] font-bold text-destructive-foreground">
              {unreadCount > 99 ? "99+" : unreadCount}
            </span>
          )}
        </Button>
      </PopoverTrigger>
      <PopoverContent className="w-80 p-0" align="end">
        <NotificationCenter
          notifications={notifications}
          isLoading={isLoading}
          onMarkAsRead={handleMarkAsRead}
          onMarkAllRead={handleMarkAllRead}
        />
      </PopoverContent>
    </Popover>
  );
}
```

### Step 5: Create `src/components/notifications/notification-center.tsx`

```tsx
"use client";

import { useId } from "react";
import { Button } from "@/components/ui/button";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Badge } from "@/components/ui/badge";
import { CheckCheck, Loader2 } from "lucide-react";
import type { NotificationRecord } from "@/lib/notifications/types";

type NotificationCenterProps = {
  notifications: NotificationRecord[];
  isLoading: boolean;
  onMarkAsRead: (notificationId: string) => void;
  onMarkAllRead: () => void;
};

function timeAgo(dateStr: string): string {
  const seconds = Math.floor(
    (Date.now() - new Date(dateStr).getTime()) / 1000
  );

  if (seconds < 60) return "just now";
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`;
  if (seconds < 86400) return `${Math.floor(seconds / 3600)}h ago`;
  if (seconds < 604800) return `${Math.floor(seconds / 86400)}d ago`;
  return new Date(dateStr).toLocaleDateString();
}

export function NotificationCenter({
  notifications,
  isLoading,
  onMarkAsRead,
  onMarkAllRead,
}: NotificationCenterProps) {
  const listId = useId();

  const unreadCount = notifications.filter((n) => !n.read).length;

  return (
    <div className="flex flex-col">
      {/* Header */}
      <div className="flex items-center justify-between border-b px-4 py-3">
        <div className="flex items-center gap-2">
          <h3 className="text-sm font-semibold">Notifications</h3>
          {unreadCount > 0 && (
            <Badge variant="secondary" className="text-xs">
              {unreadCount}
            </Badge>
          )}
        </div>
        {unreadCount > 0 && (
          <Button
            variant="ghost"
            size="sm"
            className="h-auto p-0 text-xs text-muted-foreground hover:text-foreground"
            onClick={onMarkAllRead}
          >
            <CheckCheck className="mr-1 h-3 w-3" />
            Mark all read
          </Button>
        )}
      </div>

      {/* Notification list */}
      <ScrollArea className="max-h-80">
        {isLoading && notifications.length === 0 && (
          <div className="flex items-center justify-center py-8">
            <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
          </div>
        )}

        {!isLoading && notifications.length === 0 && (
          <div className="py-8 text-center">
            <p className="text-sm text-muted-foreground">
              No notifications yet
            </p>
          </div>
        )}

        <div className="divide-y">
          {notifications.map((notification) => (
            <button
              key={`${listId}-${notification.id}`}
              type="button"
              onClick={() => {
                if (!notification.read) {
                  onMarkAsRead(notification.id);
                }
                if (notification.url) {
                  window.location.href = notification.url;
                }
              }}
              className={`flex w-full flex-col gap-1 px-4 py-3 text-left transition-colors hover:bg-muted/50 ${
                !notification.read ? "bg-primary/5" : ""
              }`}
            >
              <div className="flex items-start justify-between gap-2">
                <div className="flex-1">
                  <div className="flex items-center gap-2">
                    {!notification.read && (
                      <div className="h-2 w-2 shrink-0 rounded-full bg-primary" />
                    )}
                    <span className="text-sm font-medium">
                      {notification.title}
                    </span>
                  </div>
                  <p className="mt-0.5 text-xs text-muted-foreground line-clamp-2">
                    {notification.body}
                  </p>
                </div>
                <span className="shrink-0 text-[10px] text-muted-foreground">
                  {timeAgo(notification.createdAt)}
                </span>
              </div>
            </button>
          ))}
        </div>
      </ScrollArea>
    </div>
  );
}
```

### Step 6: Create `src/components/notifications/permission-prompt.tsx`

```tsx
"use client";

import { useState, useCallback } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Bell, Loader2, X } from "lucide-react";
import { usePush } from "@/lib/notifications/use-push";

type PermissionPromptProps = {
  onDismiss?: () => void;
};

export function PermissionPrompt({ onDismiss }: PermissionPromptProps) {
  const { isSupported, isSubscribed, isLoading, subscribe } = usePush();
  const [dismissed, setDismissed] = useState(false);
  const [isSubscribing, setIsSubscribing] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleEnable = useCallback(async () => {
    setIsSubscribing(true);
    setError(null);

    try {
      await subscribe();
      setDismissed(true);
      onDismiss?.();
    } catch (err) {
      setError(
        err instanceof Error
          ? err.message
          : "Failed to enable notifications"
      );
    } finally {
      setIsSubscribing(false);
    }
  }, [subscribe, onDismiss]);

  const handleLater = useCallback(() => {
    setDismissed(true);
    onDismiss?.();
    // Store dismissal in localStorage to avoid showing again soon
    localStorage.setItem(
      "push-prompt-dismissed",
      new Date().toISOString()
    );
  }, [onDismiss]);

  // Don't show if not supported, already subscribed, loading, or dismissed
  if (!isSupported || isSubscribed || isLoading || dismissed) {
    return null;
  }

  // Check if recently dismissed
  if (typeof window !== "undefined") {
    const dismissedAt = localStorage.getItem("push-prompt-dismissed");
    if (dismissedAt) {
    const dismissedDate = new Date(dismissedAt);
    const daysSinceDismissed =
      (Date.now() - dismissedDate.getTime()) / (1000 * 60 * 60 * 24);
    if (daysSinceDismissed < 7) {
        return null;
      }
    }
  }

  return (
    <Card className="mx-auto max-w-sm">
      <CardHeader className="pb-3">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <Bell className="h-5 w-5 text-primary" />
            <CardTitle className="text-base">Stay in the loop</CardTitle>
          </div>
          <Button
            variant="ghost"
            size="icon"
            className="h-7 w-7"
            onClick={handleLater}
          >
            <X className="h-4 w-4" />
          </Button>
        </div>
      </CardHeader>
      <CardContent className="space-y-3">
        <p className="text-sm text-muted-foreground">
          Enable push notifications to get instant alerts for room invites,
          @mentions, live calls, and meeting summaries — even when this tab
          is closed.
        </p>

        {error && (
          <p className="text-xs text-destructive">{error}</p>
        )}

        <div className="flex gap-2">
          <Button
            onClick={handleEnable}
            disabled={isSubscribing}
            className="flex-1"
          >
            {isSubscribing ? (
              <>
                <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                Enabling...
              </>
            ) : (
              "Enable Notifications"
            )}
          </Button>
          <Button variant="outline" onClick={handleLater}>
            Later
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}
```

### Step 7: Create `src/lib/db/schema/push-subscriptions.ts`

```typescript
import {
  pgTable,
  text,
  timestamp,
  uuid,
  boolean,
} from "drizzle-orm/pg-core";

export const pushSubscriptions = pgTable("push_subscriptions", {
  id: uuid("id").defaultRandom().primaryKey(),
  userId: text("user_id").notNull(),
  endpoint: text("endpoint").notNull(),
  p256dh: text("p256dh").notNull(),
  auth: text("auth").notNull(),
  createdAt: timestamp("created_at", { withTimezone: true }).defaultNow().notNull(),
});

export const notificationPreferences = pgTable("notification_preferences", {
  id: uuid("id").defaultRandom().primaryKey(),
  userId: text("user_id").notNull().unique(),
  roomInvites: boolean("room_invites").notNull().default(true),
  mentions: boolean("mentions").notNull().default(true),
  callAlerts: boolean("call_alerts").notNull().default(true),
  meetingSummaries: boolean("meeting_summaries").notNull().default(true),
});

export const notifications = pgTable("notifications", {
  id: uuid("id").defaultRandom().primaryKey(),
  userId: text("user_id").notNull(),
  title: text("title").notNull(),
  body: text("body").notNull(),
  url: text("url"),
  read: boolean("read").notNull().default(false),
  createdAt: timestamp("created_at", { withTimezone: true }).defaultNow().notNull(),
});
```

### Step 8: Add exports to `src/lib/db/schema/index.ts`

```typescript
export * from "./push-subscriptions";
```

### Step 9: Create `src/app/api/notifications/subscribe/route.ts`

```typescript
import { NextResponse } from "next/server";
import { z } from "zod/v4";
import { db } from "@/lib/db";
import { pushSubscriptions } from "@/lib/db/schema/push-subscriptions";
import { eq, and } from "drizzle-orm";
import { withAuth } from "@/lib/auth-guard";

const subscribeSchema = z.object({
  endpoint: z.string().url(),
  p256dh: z.string().min(1),
  auth: z.string().min(1),
});

export const POST = withAuth(async (request, { user }) => {
  const body = await request.json();
  const params = subscribeSchema.parse(body);

  // Check for existing subscription with same endpoint
  const existing = await db
    .select()
    .from(pushSubscriptions)
    .where(
      and(
        eq(pushSubscriptions.userId, user.id),
        eq(pushSubscriptions.endpoint, params.endpoint)
      )
    )
    .limit(1);

  if (existing.length > 0) {
    // Update existing subscription keys
    const [updated] = await db
      .update(pushSubscriptions)
      .set({
        p256dh: params.p256dh,
        auth: params.auth,
      })
      .where(eq(pushSubscriptions.id, existing[0].id))
      .returning();

    return NextResponse.json(updated);
  }

  const [subscription] = await db
    .insert(pushSubscriptions)
    .values({
      userId: user.id,
      endpoint: params.endpoint,
      p256dh: params.p256dh,
      auth: params.auth,
    })
    .returning();

  return NextResponse.json(subscription, { status: 201 });
});

const unsubscribeSchema = z.object({
  endpoint: z.string().url(),
});

export const DELETE = withAuth(async (request, { user }) => {
  const body = await request.json();
  const params = unsubscribeSchema.parse(body);

  const [deleted] = await db
    .delete(pushSubscriptions)
    .where(
      and(
        eq(pushSubscriptions.userId, user.id),
        eq(pushSubscriptions.endpoint, params.endpoint)
      )
    )
    .returning();

  if (!deleted) {
    return NextResponse.json(
      { error: "Subscription not found" },
      { status: 404 }
    );
  }

  return NextResponse.json({ success: true });
});
```

### Step 10: Create `src/app/api/notifications/preferences/route.ts`

```typescript
import { NextResponse } from "next/server";
import { z } from "zod/v4";
import { db } from "@/lib/db";
import { notificationPreferences } from "@/lib/db/schema/push-subscriptions";
import { eq } from "drizzle-orm";
import { withAuth } from "@/lib/auth-guard";

export const GET = withAuth(async (_request, { user }) => {
  const prefs = await db
    .select()
    .from(notificationPreferences)
    .where(eq(notificationPreferences.userId, user.id))
    .limit(1);

  if (prefs.length === 0) {
    // Return defaults
    return NextResponse.json({
      roomInvites: true,
      mentions: true,
      callAlerts: true,
      meetingSummaries: true,
    });
  }

  return NextResponse.json({
    roomInvites: prefs[0].roomInvites,
    mentions: prefs[0].mentions,
    callAlerts: prefs[0].callAlerts,
    meetingSummaries: prefs[0].meetingSummaries,
  });
});

const updatePrefsSchema = z.object({
  roomInvites: z.boolean().optional(),
  mentions: z.boolean().optional(),
  callAlerts: z.boolean().optional(),
  meetingSummaries: z.boolean().optional(),
});

export const PUT = withAuth(async (request, { user }) => {
  const body = await request.json();
  const params = updatePrefsSchema.parse(body);

  // Upsert preferences
  const existing = await db
    .select()
    .from(notificationPreferences)
    .where(eq(notificationPreferences.userId, user.id))
    .limit(1);

  if (existing.length > 0) {
    const [updated] = await db
      .update(notificationPreferences)
      .set({
        ...(params.roomInvites !== undefined && { roomInvites: params.roomInvites }),
        ...(params.mentions !== undefined && { mentions: params.mentions }),
        ...(params.callAlerts !== undefined && { callAlerts: params.callAlerts }),
        ...(params.meetingSummaries !== undefined && { meetingSummaries: params.meetingSummaries }),
      })
      .where(eq(notificationPreferences.id, existing[0].id))
      .returning();

    return NextResponse.json({
      roomInvites: updated.roomInvites,
      mentions: updated.mentions,
      callAlerts: updated.callAlerts,
      meetingSummaries: updated.meetingSummaries,
    });
  }

  const [created] = await db
    .insert(notificationPreferences)
    .values({
      userId: user.id,
      roomInvites: params.roomInvites ?? true,
      mentions: params.mentions ?? true,
      callAlerts: params.callAlerts ?? true,
      meetingSummaries: params.meetingSummaries ?? true,
    })
    .returning();

  return NextResponse.json({
    roomInvites: created.roomInvites,
    mentions: created.mentions,
    callAlerts: created.callAlerts,
    meetingSummaries: created.meetingSummaries,
  });
});
```

### Step 11: Create `src/app/api/notifications/route.ts`

```typescript
import { NextResponse } from "next/server";
import { z } from "zod/v4";
import { db } from "@/lib/db";
import { notifications } from "@/lib/db/schema/push-subscriptions";
import { eq, desc, and, sql } from "drizzle-orm";
import { withAuth } from "@/lib/auth-guard";

export const GET = withAuth(async (request, { user }) => {
  const { searchParams } = new URL(request.url);
  const limit = Math.min(parseInt(searchParams.get("limit") ?? "20", 10), 100);
  const offset = parseInt(searchParams.get("offset") ?? "0", 10);

  const userNotifications = await db
    .select()
    .from(notifications)
    .where(eq(notifications.userId, user.id))
    .orderBy(desc(notifications.createdAt))
    .limit(limit)
    .offset(offset);

  // Count unread
  const unreadResult = await db
    .select({ count: sql<number>`count(*)::int` })
    .from(notifications)
    .where(
      and(
        eq(notifications.userId, user.id),
        eq(notifications.read, false)
      )
    );

  const unreadCount = unreadResult[0]?.count ?? 0;

  return NextResponse.json({
    notifications: userNotifications.map((n) => ({
      id: n.id,
      userId: n.userId,
      title: n.title,
      body: n.body,
      url: n.url,
      read: n.read,
      createdAt: n.createdAt.toISOString(),
    })),
    unreadCount,
  });
});

const patchSchema = z.union([
  z.object({
    notificationId: z.string().uuid(),
    read: z.boolean(),
  }),
  z.object({
    markAllRead: z.literal(true),
  }),
]);

export const PATCH = withAuth(async (request, { user }) => {
  const body = await request.json();
  const params = patchSchema.parse(body);

  if ("markAllRead" in params) {
    await db
      .update(notifications)
      .set({ read: true })
      .where(
        and(
          eq(notifications.userId, user.id),
          eq(notifications.read, false)
        )
      );

    return NextResponse.json({ success: true });
  }

  const [updated] = await db
    .update(notifications)
    .set({ read: params.read })
    .where(
      and(
        eq(notifications.id, params.notificationId),
        eq(notifications.userId, user.id)
      )
    )
    .returning();

  if (!updated) {
    return NextResponse.json(
      { error: "Notification not found" },
      { status: 404 }
    );
  }

  return NextResponse.json({
    id: updated.id,
    userId: updated.userId,
    title: updated.title,
    body: updated.body,
    url: updated.url,
    read: updated.read,
    createdAt: updated.createdAt.toISOString(),
  });
});
```

### Step 12: Create `public/sw-push.js`

```javascript
// Service Worker for Web Push Notifications
// This file must be served from the root of the domain.

self.addEventListener("push", (event) => {
  if (!event.data) return;

  const data = event.data.json();

  const options = {
    body: data.body || "",
    icon: data.icon || "/icon-192x192.png",
    badge: "/icon-192x192.png",
    data: {
      url: data.url || "/",
    },
    actions: data.actions || [],
    vibrate: [100, 50, 100],
    tag: data.tag || "default",
    renotify: true,
  };

  event.waitUntil(
    self.registration.showNotification(data.title || "Notification", options)
  );
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();

  const url = event.notification.data?.url || "/";

  // Handle action button clicks
  if (event.action) {
    // Action-specific handling can be added here
    // For now, all actions open the URL
  }

  event.waitUntil(
    self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((clientList) => {
      // Focus existing window if available
      for (const client of clientList) {
        if (client.url === url && "focus" in client) {
          return client.focus();
        }
      }

      // Open new window
      if (self.clients.openWindow) {
        return self.clients.openWindow(url);
      }
    })
  );
});

self.addEventListener("pushsubscriptionchange", (event) => {
  // Re-subscribe when the subscription expires
  event.waitUntil(
    self.registration.pushManager
      .subscribe({
        userVisibleOnly: true,
        applicationServerKey: event.oldSubscription?.options?.applicationServerKey,
      })
      .then((subscription) => {
        const keys = subscription.toJSON().keys;

        return fetch("/api/notifications/subscribe", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            endpoint: subscription.endpoint,
            p256dh: keys?.p256dh,
            auth: keys?.auth,
          }),
        });
      })
  );
});
```

## Usage

### Subscribe a user to push notifications

```tsx
import { usePush } from "@/lib/notifications/use-push";

function MyComponent() {
  const { isSupported, isSubscribed, subscribe, unsubscribe, isLoading } = usePush();

  if (!isSupported) return <p>Push notifications not supported</p>;

  return (
    <button onClick={isSubscribed ? unsubscribe : subscribe} disabled={isLoading}>
      {isSubscribed ? "Disable Notifications" : "Enable Notifications"}
    </button>
  );
}
```

### Show the permission prompt

```tsx
import { PermissionPrompt } from "@/components/notifications/permission-prompt";

function Layout({ children }) {
  return (
    <div>
      <PermissionPrompt />
      {children}
    </div>
  );
}
```

### Add the notification bell to your header

```tsx
import { NotificationBell } from "@/components/notifications/notification-bell";

function Header() {
  return (
    <header className="flex items-center justify-between px-4 py-2">
      <h1>My App</h1>
      <NotificationBell />
    </header>
  );
}
```

### Send a push notification (server-side)

```typescript
import { sendPushNotification, sendBulkNotifications } from "@/lib/notifications/push";

// Send to one user
await sendPushNotification("user-123", {
  title: "New mention",
  body: "Alice mentioned you in #general",
  url: "/chat/general",
});

// Send to multiple users
await sendBulkNotifications(["user-123", "user-456"], {
  title: "Meeting starting",
  body: "The standup meeting is starting now",
  url: "/rooms/standup",
});
```

### Check user preferences before sending

```typescript
import { db } from "@/lib/db";
import { notificationPreferences } from "@/lib/db/schema/push-subscriptions";
import { eq } from "drizzle-orm";
import { sendPushNotification } from "@/lib/notifications/push";

async function notifyMention(userId: string, channelName: string, mentionedBy: string) {
  const prefs = await db
    .select()
    .from(notificationPreferences)
    .where(eq(notificationPreferences.userId, userId))
    .limit(1);

  // Default to true if no preferences set
  const mentionsEnabled = prefs.length === 0 || prefs[0].mentions;

  if (mentionsEnabled) {
    await sendPushNotification(userId, {
      title: `@${mentionedBy} mentioned you`,
      body: `You were mentioned in #${channelName}`,
      url: `/chat/${channelName}`,
    });
  }
}
```

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/notifications/subscribe` | Register push subscription |
| DELETE | `/api/notifications/subscribe` | Remove push subscription |
| GET | `/api/notifications/preferences` | Get notification preferences |
| PUT | `/api/notifications/preferences` | Update notification preferences |
| GET | `/api/notifications?limit=N&offset=N` | List notifications with pagination |
| PATCH | `/api/notifications` | Mark notification(s) as read |

## Acceptance Criteria

- POST `/api/notifications/subscribe` registers a device push subscription
- DELETE `/api/notifications/subscribe` removes a subscription by endpoint
- GET `/api/notifications/preferences` returns user preferences (defaults if none set)
- PUT `/api/notifications/preferences` updates individual preference flags
- GET `/api/notifications` returns paginated notifications with unread count
- PATCH with `notificationId` marks a single notification as read
- PATCH with `markAllRead: true` marks all user notifications as read
- `sendPushNotification()` delivers a push to all user devices and stores in-app notification
- `sendBulkNotifications()` sends to multiple users in parallel
- Expired subscriptions (410 Gone) are automatically cleaned up
- NotificationBell shows accurate unread count badge
- NotificationCenter displays notifications with read/unread styling
- PermissionPrompt shows once and respects 7-day dismissal cooldown
- `usePush` hook handles subscribe/unsubscribe lifecycle
- Service worker handles push events and notification clicks
- Clicking a notification opens the correct URL
- Unauthenticated API requests return 401
- `tsc` passes with no errors
- `bun run build` succeeds

## Troubleshooting

### Push notifications not arriving

**Symptoms**: `sendPushNotification` returns `{ sent: 0, failed: 0 }` or notifications don't appear.

**Cause**: No push subscriptions registered for the user.

**Fix**: Ensure the user has subscribed via the `usePush` hook. Check the `push_subscriptions` table for entries. Verify the service worker is registered at `/sw-push.js`.

### "VAPID keys not configured" error

**Symptoms**: Server throws error when trying to send push.

**Cause**: Environment variables not set.

**Fix**: Generate VAPID keys with `bunx web-push generate-vapid-keys` and add all three env vars to `.env.local`.

### Service worker not registering

**Symptoms**: `subscribe()` fails with registration error.

**Cause**: `sw-push.js` not found at the root URL path.

**Fix**: Ensure `public/sw-push.js` exists. In Next.js, files in `public/` are served from the root. Verify at `http://localhost:3000/sw-push.js`.

### "Permission denied" error

**Symptoms**: `subscribe()` throws "Notification permission denied".

**Cause**: User denied the browser notification permission prompt.

**Fix**: The user must manually enable notifications in browser settings. The `PermissionPrompt` component explains why notifications are useful before requesting permission.

### Notifications showing but not clickable

**Symptoms**: Push notification appears but clicking does nothing.

**Cause**: Service worker `notificationclick` handler not working, or `url` field missing.

**Fix**: Ensure `url` is passed in the `NotificationPayload`. Check that `sw-push.js` has the `notificationclick` event listener. The `clients.openWindow` API requires a secure context (HTTPS or localhost).
