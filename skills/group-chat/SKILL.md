---
name: group-chat
description: Real-time group chat with threads, reactions, mentions, and file attachments — Drizzle for persistence, Liveblocks for real-time delivery. Use this skill when the user says "add group chat", "setup chat", "add messaging", "team chat", or "group chat".
author: "@mattwoodco"
version: 1.0.0
created: 2026-02-18
dependencies: [auth, db, realtime, add-shadcn, storage]
---

# Group Chat

Full-featured real-time group chat with channels, threaded replies, emoji reactions, @mentions, file attachments, and typing indicators. Uses Drizzle ORM for persistence and Liveblocks for real-time message delivery and presence.

## Prerequisites

- Next.js app with `src/` directory and App Router
- `auth` skill installed (`withAuth` available at `@src/lib/auth-guard`)
- `db` skill installed (Drizzle ORM + Postgres)
- `realtime` skill installed (Liveblocks configured with `@liveblocks/react`)
- `storage` skill installed (file upload support)
- shadcn/ui initialized

## Installation

No new packages required. Uses `@liveblocks/react` (from `realtime` skill) and existing dependencies.

Install shadcn components if not already present:

```bash
bunx shadcn@latest add card badge button input textarea avatar scroll-area popover
```

## Environment Variables

No additional environment variables required. Uses `LIVEBLOCKS_SECRET_KEY` from the `realtime` skill and `DATABASE_URL` from the `db` skill.

## What Gets Created

```
src/
├── lib/
│   ├── chat/
│   │   ├── types.ts                          # Channel, Message, Thread, Reaction types
│   │   ├── use-chat-channel.ts               # Real-time chat hook with Liveblocks
│   │   └── mentions.ts                       # @mention parsing and resolution
│   └── db/
│       └── schema/
│           └── chat-messages.ts              # channels, messages, reactions Drizzle tables
├── components/
│   └── chat/
│       ├── chat-channel.tsx                  # Full chat UI: messages + input + thread sidebar
│       ├── message-bubble.tsx                # Individual message with avatar, reactions, reply
│       ├── thread-panel.tsx                  # Slide-out threaded reply panel
│       ├── typing-indicator.tsx              # "Alice is typing..." presence indicator
│       ├── reaction-picker.tsx               # Emoji reaction popover
│       └── chat-input.tsx                    # Message input with attachments and mentions
└── app/
    └── api/
        └── chat/
            ├── channels/
            │   └── route.ts                  # POST create, GET list channels
            ├── messages/
            │   └── route.ts                  # POST send, GET list with pagination
            └── reactions/
                └── route.ts                  # POST add, DELETE remove reaction
```

## Database

After applying this skill, push the schema:

```bash
bunx drizzle-kit push
```

## Setup Steps

### Step 1: Create `src/lib/db/schema/chat-messages.ts`

```typescript
import {
  pgTable,
  text,
  timestamp,
  uuid,
} from "drizzle-orm/pg-core";

export const channels = pgTable("channels", {
  id: uuid("id").defaultRandom().primaryKey(),
  name: text("name").notNull(),
  description: text("description"),
  roomId: text("room_id").notNull(),
  createdAt: timestamp("created_at", { withTimezone: true }).defaultNow().notNull(),
  createdBy: text("created_by").notNull(),
});

export const messages = pgTable("messages", {
  id: uuid("id").defaultRandom().primaryKey(),
  channelId: uuid("channel_id")
    .notNull()
    .references(() => channels.id, { onDelete: "cascade" }),
  userId: text("user_id").notNull(),
  content: text("content").notNull(),
  parentId: uuid("parent_id"),
  attachmentUrl: text("attachment_url"),
  attachmentType: text("attachment_type"),
  createdAt: timestamp("created_at", { withTimezone: true }).defaultNow().notNull(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).defaultNow().notNull(),
});

export const reactions = pgTable("reactions", {
  id: uuid("id").defaultRandom().primaryKey(),
  messageId: uuid("message_id")
    .notNull()
    .references(() => messages.id, { onDelete: "cascade" }),
  userId: text("user_id").notNull(),
  emoji: text("emoji").notNull(),
  createdAt: timestamp("created_at", { withTimezone: true }).defaultNow().notNull(),
});
```

### Step 2: Add exports to `src/lib/db/schema/index.ts`

```typescript
export * from "./chat-messages";
```

### Step 2a: Update `liveblocks.config.ts` — add `isTyping` to Presence and chat events to RoomEvent

Add `isTyping: boolean` to the `Presence` type and add the chat broadcast event types to `RoomEvent`:

```typescript
declare global {
  interface Liveblocks {
    Presence: {
      cursor: { x: number; y: number } | null;
      name: string;
      avatar: string;
      color: string;
      isTyping: boolean;
    };
    // ... keep other fields ...
    RoomEvent:
      | { type: "new-message"; message: { id: string; channelId: string; content: string; author: { id: string; name: string; image: string | null }; parentId: string | null; attachmentUrl: string | null; attachmentType: string | null; reactions: Array<{ id: string; emoji: string; userId: string; userName: string }>; replyCount: number; createdAt: string; updatedAt: string } }
      | { type: "new-reaction"; messageId: string; reaction: { id: string; emoji: string; userId: string; userName: string } }
      | { type: "remove-reaction"; messageId: string; reactionId: string };
  }
}
```

### Step 2b: Update `src/components/realtime/room-provider.tsx` — add `isTyping: false` to initial presence

In the `RealtimeRoom` component, add `isTyping: false` to the default `initialPresence`:

```typescript
initialPresence={{
  cursor: null,
  name: "",
  avatar: "",
  color: "#3b82f6",
  isTyping: false,
  ...initialPresence,
}}
```

### Step 3: Create `src/lib/chat/types.ts`

```typescript
export type Channel = {
  id: string;
  name: string;
  description: string | null;
  roomId: string;
  createdAt: string;
  createdBy: string;
};

export type MessageAuthor = {
  id: string;
  name: string;
  image: string | null;
};

export type Reaction = {
  id: string;
  emoji: string;
  userId: string;
  userName: string;
};

export type Message = {
  id: string;
  channelId: string;
  content: string;
  author: MessageAuthor;
  parentId: string | null;
  attachmentUrl: string | null;
  attachmentType: string | null;
  reactions: Reaction[];
  replyCount: number;
  createdAt: string;
  updatedAt: string;
};

export type Thread = {
  parentMessage: Message;
  replies: Message[];
};

export type ChannelMember = {
  userId: string;
  name: string;
  image: string | null;
  isOnline: boolean;
};

export type ChatPresence = {
  userId: string;
  name: string;
  isTyping: boolean;
};
```

### Step 4: Create `src/lib/chat/use-chat-channel.ts`

```typescript
"use client";

import { useState, useEffect, useCallback, useRef } from "react";
import { useBroadcastEvent, useEventListener } from "@liveblocks/react";
import type { Message, Reaction } from "./types";

type UseChatChannelOptions = {
  channelId: string;
  initialMessages?: Message[];
};

type BroadcastPayload =
  | { type: "new-message"; message: Message }
  | { type: "new-reaction"; messageId: string; reaction: Reaction }
  | { type: "remove-reaction"; messageId: string; reactionId: string };

export function useChatChannel({ channelId, initialMessages = [] }: UseChatChannelOptions) {
  const [messages, setMessages] = useState<Message[]>(initialMessages);
  const [isLoading, setIsLoading] = useState(!initialMessages.length);
  const cursorRef = useRef<string | null>(null);
  const [hasMore, setHasMore] = useState(true);

  const broadcast = useBroadcastEvent();

  // Load initial messages
  useEffect(() => {
    if (initialMessages.length > 0) return;

    let cancelled = false;
    setIsLoading(true);

    fetch(`/api/chat/messages?channelId=${channelId}&limit=50`)
      .then((res) => {
        if (!res.ok) throw new Error("Failed to load messages");
        return res.json();
      })
      .then((data: { messages: Message[]; nextCursor: string | null }) => {
        if (cancelled) return;
        setMessages(data.messages);
        cursorRef.current = data.nextCursor;
        setHasMore(data.nextCursor !== null);
      })
      .catch(() => {
        // Failed to load — start with empty
      })
      .finally(() => {
        if (!cancelled) setIsLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, [channelId, initialMessages.length]);

  // Listen for real-time events from other users
  useEventListener((event) => {
    const payload = event.event as BroadcastPayload;

    switch (payload.type) {
      case "new-message":
        setMessages((prev) => [...prev, payload.message]);
        break;

      case "new-reaction":
        setMessages((prev) =>
          prev.map((msg) =>
            msg.id === payload.messageId
              ? { ...msg, reactions: [...msg.reactions, payload.reaction] }
              : msg
          )
        );
        break;

      case "remove-reaction":
        setMessages((prev) =>
          prev.map((msg) =>
            msg.id === payload.messageId
              ? {
                  ...msg,
                  reactions: msg.reactions.filter(
                    (r) => r.id !== payload.reactionId
                  ),
                }
              : msg
          )
        );
        break;
    }
  });

  const sendMessage = useCallback(
    async (content: string, parentId?: string, attachmentUrl?: string, attachmentType?: string) => {
      const res = await fetch("/api/chat/messages", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          channelId,
          content,
          parentId: parentId ?? null,
          attachmentUrl: attachmentUrl ?? null,
          attachmentType: attachmentType ?? null,
        }),
      });

      if (!res.ok) throw new Error("Failed to send message");
      const message: Message = await res.json();

      // Optimistic update
      setMessages((prev) => [...prev, message]);

      // Broadcast to other users
      broadcast({ type: "new-message", message } satisfies BroadcastPayload);

      return message;
    },
    [channelId, broadcast]
  );

  const addReaction = useCallback(
    async (messageId: string, emoji: string) => {
      const res = await fetch("/api/chat/reactions", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ messageId, emoji }),
      });

      if (!res.ok) throw new Error("Failed to add reaction");
      const reaction: Reaction = await res.json();

      // Optimistic update
      setMessages((prev) =>
        prev.map((msg) =>
          msg.id === messageId
            ? { ...msg, reactions: [...msg.reactions, reaction] }
            : msg
        )
      );

      broadcast({
        type: "new-reaction",
        messageId,
        reaction,
      } satisfies BroadcastPayload);

      return reaction;
    },
    [broadcast]
  );

  const removeReaction = useCallback(
    async (messageId: string, reactionId: string) => {
      const res = await fetch(`/api/chat/reactions?reactionId=${reactionId}`, {
        method: "DELETE",
      });

      if (!res.ok) throw new Error("Failed to remove reaction");

      // Optimistic update
      setMessages((prev) =>
        prev.map((msg) =>
          msg.id === messageId
            ? {
                ...msg,
                reactions: msg.reactions.filter((r) => r.id !== reactionId),
              }
            : msg
        )
      );

      broadcast({
        type: "remove-reaction",
        messageId,
        reactionId,
      } satisfies BroadcastPayload);
    },
    [broadcast]
  );

  const loadMore = useCallback(async () => {
    if (!hasMore || !cursorRef.current) return;

    const res = await fetch(
      `/api/chat/messages?channelId=${channelId}&limit=50&cursor=${cursorRef.current}`
    );
    if (!res.ok) return;

    const data: { messages: Message[]; nextCursor: string | null } =
      await res.json();
    setMessages((prev) => [...data.messages, ...prev]);
    cursorRef.current = data.nextCursor;
    setHasMore(data.nextCursor !== null);
  }, [channelId, hasMore]);

  const replyToThread = useCallback(
    async (parentId: string, content: string) => {
      return sendMessage(content, parentId);
    },
    [sendMessage]
  );

  return {
    messages,
    sendMessage,
    addReaction,
    removeReaction,
    replyToThread,
    loadMore,
    hasMore,
    isLoading,
  };
}
```

### Step 5: Create `src/lib/chat/mentions.ts`

```typescript
type MentionMatch = {
  username: string;
  startIndex: number;
  endIndex: number;
};

type ResolvedUser = {
  id: string;
  name: string;
  image: string | null;
};

/**
 * Parse @mentions from message text.
 * Matches patterns like @alice, @bob-smith, @user_123
 */
export function parseMentions(text: string): MentionMatch[] {
  const mentionRegex = /@([\w-]+)/g;
  const mentions: MentionMatch[] = [];
  let match: RegExpExecArray | null;

  match = mentionRegex.exec(text);
  while (match !== null) {
    mentions.push({
      username: match[1],
      startIndex: match.index,
      endIndex: match.index + match[0].length,
    });
    match = mentionRegex.exec(text);
  }

  return mentions;
}

/**
 * Resolve mention usernames to user objects.
 * Returns only users that were found.
 */
export function resolveMentions(
  mentions: MentionMatch[],
  users: ResolvedUser[]
): Map<string, ResolvedUser> {
  const resolved = new Map<string, ResolvedUser>();

  for (const mention of mentions) {
    const user = users.find(
      (u) => u.name.toLowerCase().replace(/\s+/g, "-") === mention.username.toLowerCase()
    );
    if (user) {
      resolved.set(mention.username, user);
    }
  }

  return resolved;
}

/**
 * Render message text with highlighted @mentions.
 * Returns an array of text segments with mention metadata.
 */
export function segmentMentions(
  text: string,
  resolvedUsers: Map<string, ResolvedUser>
): Array<{ type: "text"; value: string } | { type: "mention"; username: string; userId: string }> {
  const mentions = parseMentions(text);
  if (mentions.length === 0) {
    return [{ type: "text", value: text }];
  }

  const segments: Array<
    { type: "text"; value: string } | { type: "mention"; username: string; userId: string }
  > = [];
  let lastIndex = 0;

  for (const mention of mentions) {
    if (mention.startIndex > lastIndex) {
      segments.push({
        type: "text",
        value: text.slice(lastIndex, mention.startIndex),
      });
    }

    const resolved = resolvedUsers.get(mention.username);
    if (resolved) {
      segments.push({
        type: "mention",
        username: mention.username,
        userId: resolved.id,
      });
    } else {
      segments.push({
        type: "text",
        value: text.slice(mention.startIndex, mention.endIndex),
      });
    }

    lastIndex = mention.endIndex;
  }

  if (lastIndex < text.length) {
    segments.push({ type: "text", value: text.slice(lastIndex) });
  }

  return segments;
}
```

### Step 6: Create `src/components/chat/chat-channel.tsx`

```tsx
"use client";

import { useState, useRef, useEffect, useId } from "react";
import { ScrollArea } from "@/components/ui/scroll-area";
import { MessageBubble } from "./message-bubble";
import { ChatInput } from "./chat-input";
import { ThreadPanel } from "./thread-panel";
import { TypingIndicator } from "./typing-indicator";
import { useChatChannel } from "@src/lib/chat/use-chat-channel";
import type { Message } from "@src/lib/chat/types";
import { Loader2 } from "lucide-react";

type ChatChannelProps = {
  channelId: string;
  channelName: string;
  currentUserId: string;
};

export function ChatChannel({ channelId, channelName, currentUserId }: ChatChannelProps) {
  const messageListId = useId();
  const scrollRef = useRef<HTMLDivElement>(null);
  const [activeThread, setActiveThread] = useState<Message | null>(null);

  const {
    messages,
    sendMessage,
    addReaction,
    removeReaction,
    replyToThread,
    loadMore,
    hasMore,
    isLoading,
  } = useChatChannel({ channelId });

  // Auto-scroll to bottom on new messages
  // biome-ignore lint/correctness/useExhaustiveDependencies: scroll on every message change
  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [messages]);

  const handleSend = async (content: string, attachmentUrl?: string, attachmentType?: string) => {
    await sendMessage(content, undefined, attachmentUrl, attachmentType);
  };

  const handleReply = (message: Message) => {
    setActiveThread(message);
  };

  const handleCloseThread = () => {
    setActiveThread(null);
  };

  const threadReplies = activeThread
    ? messages.filter((m) => m.parentId === activeThread.id)
    : [];

  // Filter to top-level messages only
  const topLevelMessages = messages.filter((m) => m.parentId === null);

  if (isLoading) {
    return (
      <div className="flex h-full items-center justify-center">
        <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
      </div>
    );
  }

  return (
    <div className="flex h-full">
      {/* Main chat area */}
      <div className="flex flex-1 flex-col">
        {/* Channel header */}
        <div className="flex items-center border-b px-4 py-3">
          <h2 className="text-sm font-semibold">#{channelName}</h2>
        </div>

        {/* Message list */}
        <ScrollArea className="flex-1" ref={scrollRef}>
          <div className="flex flex-col gap-1 p-4">
            {hasMore && (
              <button
                type="button"
                onClick={loadMore}
                className="self-center text-xs text-muted-foreground hover:text-foreground"
              >
                Load older messages
              </button>
            )}

            {topLevelMessages.length === 0 && (
              <div className="flex h-40 items-center justify-center text-muted-foreground">
                <p className="text-sm">
                  No messages yet. Start the conversation!
                </p>
              </div>
            )}

            {topLevelMessages.map((message) => (
              <MessageBubble
                key={`${messageListId}-${message.id}`}
                message={message}
                currentUserId={currentUserId}
                onReply={() => handleReply(message)}
                onAddReaction={(emoji) => addReaction(message.id, emoji)}
                onRemoveReaction={(reactionId) =>
                  removeReaction(message.id, reactionId)
                }
              />
            ))}
          </div>
        </ScrollArea>

        {/* Typing indicator */}
        <TypingIndicator />

        {/* Message input */}
        <div className="border-t p-3">
          <ChatInput
            onSend={handleSend}
            placeholder={`Message #${channelName}`}
          />
        </div>
      </div>

      {/* Thread panel */}
      {activeThread && (
        <ThreadPanel
          parentMessage={activeThread}
          replies={threadReplies}
          currentUserId={currentUserId}
          onClose={handleCloseThread}
          onSendReply={(content) => replyToThread(activeThread.id, content)}
          onAddReaction={addReaction}
          onRemoveReaction={removeReaction}
        />
      )}
    </div>
  );
}
```

### Step 7: Create `src/components/chat/message-bubble.tsx`

```tsx
"use client";

import { useId, useState } from "react";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { ReactionPicker } from "./reaction-picker";
import { MessageSquare, SmilePlus, ImageIcon, FileIcon } from "lucide-react";
import type { Message } from "@src/lib/chat/types";
import { segmentMentions } from "@src/lib/chat/mentions";

type MessageBubbleProps = {
  message: Message;
  currentUserId: string;
  onReply: () => void;
  onAddReaction: (emoji: string) => void;
  onRemoveReaction: (reactionId: string) => void;
};

function formatTime(dateStr: string): string {
  const date = new Date(dateStr);
  return date.toLocaleTimeString("en-US", {
    hour: "numeric",
    minute: "2-digit",
    hour12: true,
  });
}

function getInitials(name: string): string {
  return name
    .split(" ")
    .map((part) => part[0])
    .join("")
    .toUpperCase()
    .slice(0, 2);
}

export function MessageBubble({
  message,
  currentUserId,
  onReply,
  onAddReaction,
  onRemoveReaction,
}: MessageBubbleProps) {
  const reactionListId = useId();
  const [showActions, setShowActions] = useState(false);
  const [showReactionPicker, setShowReactionPicker] = useState(false);

  // Render content with mention highlights
  const segments = segmentMentions(message.content, new Map());

  // Group reactions by emoji
  const reactionGroups = new Map<string, { count: number; userReactionId: string | null; users: string[] }>();
  for (const reaction of message.reactions) {
    const existing = reactionGroups.get(reaction.emoji);
    if (existing) {
      existing.count += 1;
      existing.users.push(reaction.userName);
      if (reaction.userId === currentUserId) {
        existing.userReactionId = reaction.id;
      }
    } else {
      reactionGroups.set(reaction.emoji, {
        count: 1,
        userReactionId: reaction.userId === currentUserId ? reaction.id : null,
        users: [reaction.userName],
      });
    }
  }

  return (
    <div
      className="group relative flex gap-3 rounded-md px-2 py-1.5 hover:bg-muted/50"
      onMouseEnter={() => setShowActions(true)}
      onMouseLeave={() => {
        setShowActions(false);
        setShowReactionPicker(false);
      }}
    >
      {/* Avatar */}
      <Avatar className="h-8 w-8 shrink-0">
        {message.author.image && <AvatarImage src={message.author.image} alt={message.author.name} />}
        <AvatarFallback className="text-xs">
          {getInitials(message.author.name)}
        </AvatarFallback>
      </Avatar>

      {/* Content */}
      <div className="flex-1 min-w-0">
        <div className="flex items-baseline gap-2">
          <span className="text-sm font-semibold">{message.author.name}</span>
          <span className="text-xs text-muted-foreground">
            {formatTime(message.createdAt)}
          </span>
        </div>

        {/* Message text with mentions */}
        <div className="text-sm">
          {segments.map((segment, idx) => {
            if (segment.type === "mention") {
              return (
                <span
                  key={`mention-${segment.userId}-${idx}`}
                  className="rounded bg-primary/10 px-1 font-medium text-primary"
                >
                  @{segment.username}
                </span>
              );
            }
            return <span key={`text-${idx}`}>{segment.value}</span>;
          })}
        </div>

        {/* Attachment preview */}
        {message.attachmentUrl && (
          <div className="mt-2">
            {message.attachmentType?.startsWith("image/") ? (
              <div className="relative max-w-xs overflow-hidden rounded-lg border">
                <img
                  src={message.attachmentUrl}
                  alt="Attachment"
                  className="h-auto w-full"
                />
              </div>
            ) : (
              <a
                href={message.attachmentUrl}
                target="_blank"
                rel="noopener noreferrer"
                className="flex items-center gap-2 rounded-lg border p-2 text-sm hover:bg-muted"
              >
                <FileIcon className="h-4 w-4" />
                <span>Attachment</span>
              </a>
            )}
          </div>
        )}

        {/* Reactions bar */}
        {reactionGroups.size > 0 && (
          <div className="mt-1 flex flex-wrap gap-1">
            {Array.from(reactionGroups.entries()).map(([emoji, group]) => (
              <button
                key={`${reactionListId}-${emoji}`}
                type="button"
                onClick={() => {
                  if (group.userReactionId) {
                    onRemoveReaction(group.userReactionId);
                  } else {
                    onAddReaction(emoji);
                  }
                }}
                className={`flex items-center gap-1 rounded-full border px-2 py-0.5 text-xs transition-colors hover:bg-muted ${
                  group.userReactionId
                    ? "border-primary/50 bg-primary/10"
                    : ""
                }`}
                title={group.users.join(", ")}
              >
                <span>{emoji}</span>
                <span>{group.count}</span>
              </button>
            ))}
          </div>
        )}

        {/* Reply count */}
        {message.replyCount > 0 && (
          <button
            type="button"
            onClick={onReply}
            className="mt-1 flex items-center gap-1 text-xs text-primary hover:underline"
          >
            <MessageSquare className="h-3 w-3" />
            {message.replyCount} {message.replyCount === 1 ? "reply" : "replies"}
          </button>
        )}
      </div>

      {/* Hover action bar */}
      {showActions && (
        <div className="absolute -top-3 right-2 flex items-center gap-0.5 rounded-md border bg-background p-0.5 shadow-sm">
          <ReactionPicker
            open={showReactionPicker}
            onOpenChange={setShowReactionPicker}
            onSelect={(emoji) => {
              onAddReaction(emoji);
              setShowReactionPicker(false);
            }}
          >
            <Button variant="ghost" size="icon" className="h-7 w-7">
              <SmilePlus className="h-4 w-4" />
            </Button>
          </ReactionPicker>
          <Button
            variant="ghost"
            size="icon"
            className="h-7 w-7"
            onClick={onReply}
          >
            <MessageSquare className="h-4 w-4" />
          </Button>
        </div>
      )}
    </div>
  );
}
```

### Step 8: Create `src/components/chat/thread-panel.tsx`

```tsx
"use client";

import { useId } from "react";
import { Button } from "@/components/ui/button";
import { ScrollArea } from "@/components/ui/scroll-area";
import { X } from "lucide-react";
import { MessageBubble } from "./message-bubble";
import { ChatInput } from "./chat-input";
import type { Message } from "@src/lib/chat/types";

type ThreadPanelProps = {
  parentMessage: Message;
  replies: Message[];
  currentUserId: string;
  onClose: () => void;
  onSendReply: (content: string) => Promise<Message>;
  onAddReaction: (messageId: string, emoji: string) => Promise<unknown>;
  onRemoveReaction: (messageId: string, reactionId: string) => Promise<void>;
};

export function ThreadPanel({
  parentMessage,
  replies,
  currentUserId,
  onClose,
  onSendReply,
  onAddReaction,
  onRemoveReaction,
}: ThreadPanelProps) {
  const listId = useId();

  return (
    <div className="flex w-80 flex-col border-l bg-background">
      {/* Thread header */}
      <div className="flex items-center justify-between border-b px-4 py-3">
        <h3 className="text-sm font-semibold">Thread</h3>
        <Button variant="ghost" size="icon" className="h-7 w-7" onClick={onClose}>
          <X className="h-4 w-4" />
        </Button>
      </div>

      {/* Parent message */}
      <div className="border-b px-2 py-2">
        <MessageBubble
          message={parentMessage}
          currentUserId={currentUserId}
          onReply={() => {}}
          onAddReaction={(emoji) => addReactionWrapped(parentMessage.id, emoji)}
          onRemoveReaction={(reactionId) =>
            removeReactionWrapped(parentMessage.id, reactionId)
          }
        />
      </div>

      {/* Replies */}
      <ScrollArea className="flex-1">
        <div className="flex flex-col gap-1 p-2">
          {replies.length === 0 && (
            <p className="p-4 text-center text-xs text-muted-foreground">
              No replies yet
            </p>
          )}
          {replies.map((reply) => (
            <MessageBubble
              key={`${listId}-${reply.id}`}
              message={reply}
              currentUserId={currentUserId}
              onReply={() => {}}
              onAddReaction={(emoji) => addReactionWrapped(reply.id, emoji)}
              onRemoveReaction={(reactionId) =>
                removeReactionWrapped(reply.id, reactionId)
              }
            />
          ))}
        </div>
      </ScrollArea>

      {/* Reply input */}
      <div className="border-t p-3">
        <ChatInput
          onSend={(content) => onSendReply(content)}
          placeholder="Reply in thread..."
          compact
        />
      </div>
    </div>
  );

  function addReactionWrapped(messageId: string, emoji: string) {
    void onAddReaction(messageId, emoji);
  }

  function removeReactionWrapped(messageId: string, reactionId: string) {
    void onRemoveReaction(messageId, reactionId);
  }
}
```

### Step 9: Create `src/components/chat/typing-indicator.tsx`

```tsx
"use client";

import { useOthers } from "@liveblocks/react";

export function TypingIndicator() {
  const others = useOthers();

  const typingUsers = others.filter(
    (other) => (other.presence as { isTyping?: boolean })?.isTyping === true
  );

  if (typingUsers.length === 0) return null;

  const names = typingUsers.map(
    (user) =>
      (user.info as { name?: string })?.name ??
      (user.presence as { name?: string })?.name ??
      "Someone"
  );

  let text: string;
  if (names.length === 1) {
    text = `${names[0]} is typing...`;
  } else if (names.length === 2) {
    text = `${names[0]} and ${names[1]} are typing...`;
  } else {
    text = `${names[0]} and ${names.length - 1} others are typing...`;
  }

  return (
    <div className="px-4 py-1">
      <p className="text-xs text-muted-foreground animate-pulse">{text}</p>
    </div>
  );
}
```

### Step 10: Create `src/components/chat/reaction-picker.tsx`

```tsx
"use client";

import type { ReactNode } from "react";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { Button } from "@/components/ui/button";

const COMMON_REACTIONS = [
  { emoji: "\uD83D\uDC4D", label: "thumbs up" },
  { emoji: "\u2764\uFE0F", label: "heart" },
  { emoji: "\uD83D\uDE02", label: "joy" },
  { emoji: "\uD83C\uDF89", label: "party" },
  { emoji: "\uD83D\uDE2E", label: "surprised" },
  { emoji: "\uD83D\uDE22", label: "sad" },
  { emoji: "\uD83D\uDD25", label: "fire" },
  { emoji: "\uD83D\uDE4F", label: "pray" },
  { emoji: "\uD83D\uDCAF", label: "100" },
  { emoji: "\uD83D\uDC40", label: "eyes" },
  { emoji: "\u2705", label: "check" },
  { emoji: "\u274C", label: "cross" },
];

type ReactionPickerProps = {
  children: ReactNode;
  onSelect: (emoji: string) => void;
  open?: boolean;
  onOpenChange?: (open: boolean) => void;
};

export function ReactionPicker({
  children,
  onSelect,
  open,
  onOpenChange,
}: ReactionPickerProps) {
  return (
    <Popover open={open} onOpenChange={onOpenChange}>
      <PopoverTrigger asChild>{children}</PopoverTrigger>
      <PopoverContent className="w-auto p-2" align="start">
        <div className="grid grid-cols-6 gap-1">
          {COMMON_REACTIONS.map((reaction) => (
            <Button
              key={reaction.label}
              variant="ghost"
              size="icon"
              className="h-8 w-8 text-lg"
              onClick={() => onSelect(reaction.emoji)}
              title={reaction.label}
            >
              {reaction.emoji}
            </Button>
          ))}
        </div>
      </PopoverContent>
    </Popover>
  );
}
```

### Step 11: Create `src/components/chat/chat-input.tsx`

```tsx
"use client";

import { useState, useCallback, useRef, useEffect } from "react";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Paperclip, Send, SmilePlus, Loader2 } from "lucide-react";
import { useUpdateMyPresence } from "@liveblocks/react";

type ChatInputProps = {
  onSend: (content: string, attachmentUrl?: string, attachmentType?: string) => Promise<unknown> | void;
  placeholder?: string;
  compact?: boolean;
};

const COMMON_EMOJIS = [
  "\uD83D\uDC4D", "\u2764\uFE0F", "\uD83D\uDE02", "\uD83C\uDF89",
  "\uD83D\uDE2E", "\uD83D\uDD25", "\uD83D\uDE4F", "\uD83D\uDCAF",
];

export function ChatInput({ onSend, placeholder = "Type a message...", compact = false }: ChatInputProps) {
  const [value, setValue] = useState("");
  const [isSending, setIsSending] = useState(false);
  const [isUploading, setIsUploading] = useState(false);
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const updatePresence = useUpdateMyPresence();
  const typingTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Update typing presence
  const handleTyping = useCallback(() => {
    updatePresence({ isTyping: true });

    if (typingTimeoutRef.current) {
      clearTimeout(typingTimeoutRef.current);
    }

    typingTimeoutRef.current = setTimeout(() => {
      updatePresence({ isTyping: false });
    }, 2000);
  }, [updatePresence]);

  // Clean up typing timeout on unmount
  useEffect(() => {
    return () => {
      if (typingTimeoutRef.current) {
        clearTimeout(typingTimeoutRef.current);
      }
    };
  }, []);

  const handleSend = useCallback(async () => {
    const trimmed = value.trim();
    if (!trimmed || isSending) return;

    setIsSending(true);
    updatePresence({ isTyping: false });

    try {
      await onSend(trimmed);
      setValue("");
      textareaRef.current?.focus();
    } catch {
      // Keep the value on error so user can retry
    } finally {
      setIsSending(false);
    }
  }, [value, isSending, onSend, updatePresence]);

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if (e.key === "Enter" && !e.shiftKey) {
        e.preventDefault();
        void handleSend();
      }
    },
    [handleSend]
  );

  const handleFileSelect = useCallback(
    async (e: React.ChangeEvent<HTMLInputElement>) => {
      const file = e.target.files?.[0];
      if (!file) return;

      setIsUploading(true);
      try {
        // Upload via storage skill
        const formData = new FormData();
        formData.append("file", file);
        formData.append("path", `chat-attachments/${Date.now()}-${file.name}`);

        const res = await fetch("/api/storage/upload", {
          method: "POST",
          body: formData,
        });

        if (!res.ok) throw new Error("Upload failed");
        const data: { url: string } = await res.json();

        await onSend(file.name, data.url, file.type);
      } catch {
        // Upload failed — ignore
      } finally {
        setIsUploading(false);
        // Reset file input
        if (fileInputRef.current) {
          fileInputRef.current.value = "";
        }
      }
    },
    [onSend]
  );

  const handleEmojiInsert = useCallback((emoji: string) => {
    setValue((prev) => prev + emoji);
    textareaRef.current?.focus();
  }, []);

  return (
    <div className="flex items-end gap-2">
      {/* File attach button */}
      <input
        ref={fileInputRef}
        type="file"
        className="hidden"
        onChange={handleFileSelect}
      />
      <Button
        variant="ghost"
        size="icon"
        className={compact ? "h-8 w-8" : "h-9 w-9"}
        disabled={isUploading}
        onClick={() => fileInputRef.current?.click()}
      >
        {isUploading ? (
          <Loader2 className="h-4 w-4 animate-spin" />
        ) : (
          <Paperclip className="h-4 w-4" />
        )}
      </Button>

      {/* Text input */}
      <Textarea
        ref={textareaRef}
        value={value}
        onChange={(e) => {
          setValue(e.target.value);
          handleTyping();
        }}
        onKeyDown={handleKeyDown}
        placeholder={placeholder}
        disabled={isSending}
        rows={1}
        className={`flex-1 resize-none ${compact ? "min-h-8 text-sm" : "min-h-10"}`}
      />

      {/* Emoji picker */}
      <Popover>
        <PopoverTrigger asChild>
          <Button
            variant="ghost"
            size="icon"
            className={compact ? "h-8 w-8" : "h-9 w-9"}
          >
            <SmilePlus className="h-4 w-4" />
          </Button>
        </PopoverTrigger>
        <PopoverContent className="w-auto p-2" align="end">
          <div className="flex gap-1">
            {COMMON_EMOJIS.map((emoji) => (
              <Button
                key={emoji}
                variant="ghost"
                size="icon"
                className="h-8 w-8 text-lg"
                onClick={() => handleEmojiInsert(emoji)}
              >
                {emoji}
              </Button>
            ))}
          </div>
        </PopoverContent>
      </Popover>

      {/* Send button */}
      <Button
        size="icon"
        className={compact ? "h-8 w-8" : "h-9 w-9"}
        disabled={!value.trim() || isSending}
        onClick={() => void handleSend()}
      >
        {isSending ? (
          <Loader2 className="h-4 w-4 animate-spin" />
        ) : (
          <Send className="h-4 w-4" />
        )}
      </Button>
    </div>
  );
}
```

### Step 12: Create `src/app/api/chat/channels/route.ts`

```typescript
import { NextResponse } from "next/server";
import { z } from "zod/v4";
import { db } from "@src/lib/db";
import { channels } from "@src/lib/db/schema/chat-messages";
import { eq, desc } from "drizzle-orm";
import { withAuth } from "@src/lib/auth-guard";

const createChannelSchema = z.object({
  name: z.string().min(1).max(100),
  description: z.string().max(500).optional(),
  roomId: z.string().min(1),
});

export const POST = withAuth(async (request, { user }) => {
  const body = await request.json();
  const params = createChannelSchema.parse(body);

  const [channel] = await db
    .insert(channels)
    .values({
      name: params.name,
      description: params.description ?? null,
      roomId: params.roomId,
      createdBy: user.id,
    })
    .returning();

  return NextResponse.json(channel, { status: 201 });
});

export const GET = withAuth(async (request) => {
  const { searchParams } = new URL(request.url);
  const roomId = searchParams.get("roomId");

  if (!roomId) {
    return NextResponse.json(
      { error: "roomId query parameter is required" },
      { status: 400 }
    );
  }

  const channelList = await db
    .select()
    .from(channels)
    .where(eq(channels.roomId, roomId))
    .orderBy(desc(channels.createdAt));

  return NextResponse.json(channelList);
});
```

### Step 13: Create `src/app/api/chat/messages/route.ts`

```typescript
import { NextResponse } from "next/server";
import { z } from "zod/v4";
import { db } from "@src/lib/db";
import { messages, reactions } from "@src/lib/db/schema/chat-messages";
import { eq, desc, lt, and, sql, isNull } from "drizzle-orm";
import { withAuth } from "@src/lib/auth-guard";

const sendMessageSchema = z.object({
  channelId: z.string().uuid(),
  content: z.string().min(1).max(5000),
  parentId: z.string().uuid().nullable(),
  attachmentUrl: z.string().url().nullable(),
  attachmentType: z.string().nullable(),
});

export const POST = withAuth(async (request, { user }) => {
  const body = await request.json();
  const params = sendMessageSchema.parse(body);

  const [message] = await db
    .insert(messages)
    .values({
      channelId: params.channelId,
      userId: user.id,
      content: params.content,
      parentId: params.parentId,
      attachmentUrl: params.attachmentUrl,
      attachmentType: params.attachmentType,
    })
    .returning();

  // Return message with author info and empty reactions
  const authorName = user.name ?? user.email ?? "Unknown";
  const authorImage = user.image ?? null;

  return NextResponse.json({
    id: message.id,
    channelId: message.channelId,
    content: message.content,
    author: {
      id: user.id,
      name: authorName,
      image: authorImage,
    },
    parentId: message.parentId,
    attachmentUrl: message.attachmentUrl,
    attachmentType: message.attachmentType,
    reactions: [],
    replyCount: 0,
    createdAt: message.createdAt.toISOString(),
    updatedAt: message.updatedAt.toISOString(),
  });
});

export const GET = withAuth(async (request) => {
  const { searchParams } = new URL(request.url);
  const channelId = searchParams.get("channelId");
  const cursor = searchParams.get("cursor");
  const limit = Math.min(parseInt(searchParams.get("limit") ?? "50", 10), 100);

  if (!channelId) {
    return NextResponse.json(
      { error: "channelId query parameter is required" },
      { status: 400 }
    );
  }

  // Build query conditions
  const conditions = [eq(messages.channelId, channelId)];
  if (cursor) {
    conditions.push(lt(messages.createdAt, new Date(cursor)));
  }

  const messageRows = await db
    .select()
    .from(messages)
    .where(and(...conditions))
    .orderBy(desc(messages.createdAt))
    .limit(limit + 1);

  const hasMore = messageRows.length > limit;
  const resultMessages = hasMore ? messageRows.slice(0, limit) : messageRows;

  // Fetch reactions for these messages
  const messageIds = resultMessages.map((m) => m.id);
  let reactionRows: Array<{
    id: string;
    messageId: string;
    userId: string;
    emoji: string;
    createdAt: Date;
  }> = [];

  if (messageIds.length > 0) {
    reactionRows = await db
      .select()
      .from(reactions)
      .where(
        sql`${reactions.messageId} = ANY(${sql`ARRAY[${sql.join(
          messageIds.map((id) => sql`${id}::uuid`),
          sql`, `
        )}]`})`
      );
  }

  // Count replies for each message
  const replyCounts = new Map<string, number>();
  if (messageIds.length > 0) {
    const replyCountRows = await db
      .select({
        parentId: messages.parentId,
        count: sql<number>`count(*)::int`,
      })
      .from(messages)
      .where(
        sql`${messages.parentId} = ANY(${sql`ARRAY[${sql.join(
          messageIds.map((id) => sql`${id}::uuid`),
          sql`, `
        )}]`})`
      )
      .groupBy(messages.parentId);

    for (const row of replyCountRows) {
      if (row.parentId) {
        replyCounts.set(row.parentId, row.count);
      }
    }
  }

  // Group reactions by message
  const reactionsByMessage = new Map<string, typeof reactionRows>();
  for (const reaction of reactionRows) {
    const existing = reactionsByMessage.get(reaction.messageId) ?? [];
    existing.push(reaction);
    reactionsByMessage.set(reaction.messageId, existing);
  }

  // Format response
  const formattedMessages = resultMessages.reverse().map((msg) => ({
    id: msg.id,
    channelId: msg.channelId,
    content: msg.content,
    author: {
      id: msg.userId,
      name: msg.userId,
      image: null,
    },
    parentId: msg.parentId,
    attachmentUrl: msg.attachmentUrl,
    attachmentType: msg.attachmentType,
    reactions: (reactionsByMessage.get(msg.id) ?? []).map((r) => ({
      id: r.id,
      emoji: r.emoji,
      userId: r.userId,
      userName: r.userId,
    })),
    replyCount: replyCounts.get(msg.id) ?? 0,
    createdAt: msg.createdAt.toISOString(),
    updatedAt: msg.updatedAt.toISOString(),
  }));

  const nextCursor = hasMore
    ? resultMessages[resultMessages.length - 1].createdAt.toISOString()
    : null;

  return NextResponse.json({
    messages: formattedMessages,
    nextCursor,
  });
});
```

### Step 14: Create `src/app/api/chat/reactions/route.ts`

```typescript
import { NextResponse } from "next/server";
import { z } from "zod/v4";
import { db } from "@src/lib/db";
import { reactions } from "@src/lib/db/schema/chat-messages";
import { eq, and } from "drizzle-orm";
import { withAuth } from "@src/lib/auth-guard";

const addReactionSchema = z.object({
  messageId: z.string().uuid(),
  emoji: z.string().min(1).max(10),
});

export const POST = withAuth(async (request, { user }) => {
  const body = await request.json();
  const params = addReactionSchema.parse(body);

  // Check for duplicate reaction
  const existing = await db
    .select()
    .from(reactions)
    .where(
      and(
        eq(reactions.messageId, params.messageId),
        eq(reactions.userId, user.id),
        eq(reactions.emoji, params.emoji)
      )
    )
    .limit(1);

  if (existing.length > 0) {
    return NextResponse.json(
      {
        id: existing[0].id,
        emoji: existing[0].emoji,
        userId: user.id,
        userName: user.name ?? user.email ?? "Unknown",
      },
      { status: 200 }
    );
  }

  const [reaction] = await db
    .insert(reactions)
    .values({
      messageId: params.messageId,
      userId: user.id,
      emoji: params.emoji,
    })
    .returning();

  return NextResponse.json(
    {
      id: reaction.id,
      emoji: reaction.emoji,
      userId: user.id,
      userName: user.name ?? user.email ?? "Unknown",
    },
    { status: 201 }
  );
});

export const DELETE = withAuth(async (request, { user }) => {
  const { searchParams } = new URL(request.url);
  const reactionId = searchParams.get("reactionId");

  if (!reactionId) {
    return NextResponse.json(
      { error: "reactionId query parameter is required" },
      { status: 400 }
    );
  }

  const [deleted] = await db
    .delete(reactions)
    .where(
      and(
        eq(reactions.id, reactionId),
        eq(reactions.userId, user.id)
      )
    )
    .returning();

  if (!deleted) {
    return NextResponse.json(
      { error: "Reaction not found or not owned by user" },
      { status: 404 }
    );
  }

  return NextResponse.json({ success: true });
});
```

## Usage

### Create a channel

```typescript
const response = await fetch("/api/chat/channels", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    name: "general",
    description: "General discussion",
    roomId: "room-123",
  }),
});
const channel = await response.json();
```

### List channels for a room

```typescript
const response = await fetch("/api/chat/channels?roomId=room-123");
const channels = await response.json();
```

### Send a message

```typescript
const response = await fetch("/api/chat/messages", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    channelId: "channel-uuid",
    content: "Hello everyone! @alice what do you think?",
    parentId: null,
    attachmentUrl: null,
    attachmentType: null,
  }),
});
const message = await response.json();
```

### Load messages with pagination

```typescript
// First page
const response = await fetch("/api/chat/messages?channelId=uuid&limit=50");
const { messages, nextCursor } = await response.json();

// Next page
if (nextCursor) {
  const next = await fetch(
    `/api/chat/messages?channelId=uuid&limit=50&cursor=${nextCursor}`
  );
}
```

### Render the chat UI

```tsx
import { ChatChannel } from "@/components/chat/chat-channel";
import { RoomProvider } from "@liveblocks/react";

function ChatRoom() {
  return (
    <RoomProvider id="room-123" initialPresence={{ isTyping: false }}>
      <ChatChannel
        channelId="channel-uuid"
        channelName="general"
        currentUserId="user-123"
      />
    </RoomProvider>
  );
}
```

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/chat/channels` | Create a channel |
| GET | `/api/chat/channels?roomId=X` | List channels for a room |
| POST | `/api/chat/messages` | Send a message |
| GET | `/api/chat/messages?channelId=X` | List messages with cursor pagination |
| POST | `/api/chat/reactions` | Add a reaction |
| DELETE | `/api/chat/reactions?reactionId=X` | Remove a reaction |

## Acceptance Criteria

- POST `/api/chat/channels` creates a channel tied to a roomId
- GET `/api/chat/channels?roomId=X` lists channels for a room
- POST `/api/chat/messages` sends a message and returns it with author info
- GET `/api/chat/messages?channelId=X` returns messages with cursor-based pagination
- Messages include reactions grouped by emoji and reply counts
- POST `/api/chat/reactions` adds an emoji reaction (idempotent for same user+emoji)
- DELETE `/api/chat/reactions?reactionId=X` removes user's own reaction
- ChatChannel component renders message list, input, and thread sidebar
- Real-time message delivery works via Liveblocks broadcast events
- Typing indicator shows when other users are typing
- File attachments upload via the storage skill and display inline
- @mentions are parsed and highlighted in message text
- Threaded replies display in a slide-out panel
- Unauthenticated requests return 401
- `tsc` passes with no errors
- `bun run build` succeeds

## Troubleshooting

### Messages not appearing in real-time

**Symptoms**: Sent messages only appear after page refresh.

**Cause**: Liveblocks room not connected or event listener not registered.

**Fix**: Ensure the `ChatChannel` component is wrapped in a `<RoomProvider>` from `@liveblocks/react`. Check that the `LIVEBLOCKS_SECRET_KEY` is set and the realtime skill is properly configured.

### "channelId query parameter is required"

**Symptoms**: GET `/api/chat/messages` returns 400.

**Cause**: Missing `channelId` in the query string.

**Fix**: Always pass `?channelId=uuid` when fetching messages.

### File upload fails

**Symptoms**: Attachment button shows error or spinner never stops.

**Cause**: The storage skill's upload endpoint (`/api/storage/upload`) is not configured.

**Fix**: Ensure the `storage` skill is installed and the upload API route is working. Check storage provider credentials.

### Typing indicator not showing

**Symptoms**: Other users don't see "X is typing..." text.

**Cause**: Presence updates not being sent or received.

**Fix**: Ensure `useUpdateMyPresence` is available (requires `<RoomProvider>` wrapper) and that the initial presence includes `{ isTyping: false }`.
