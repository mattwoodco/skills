---
name: copy-preview
description: Platform-specific copy preview cards — tweet, Instagram caption, LinkedIn post, and email subject line mockups for previewing AI-generated copy in context. Use this skill when the user says "add copy preview", "platform preview", "social preview cards", "tweet preview", or "caption preview".
author: "@mattwoodco"
version: 1.0.0
created: 2026-02-17
updated: 2026-02-17
dependencies: [add-shadcn]
---

# Copy Preview

A set of realistic platform mockup components for previewing AI-generated copy in context. Supports Twitter/X, Instagram, LinkedIn, and email. Exposed through a single unified `<CopyPreview>` component that selects the correct card from a `platform` prop.

## Prerequisites

- Next.js app with App Router (no `src/` directory)
- shadcn/ui installed (from the `add-shadcn` skill)
- `@phosphor-icons/react` installed

## Installation

```bash
bun add @phosphor-icons/react
bunx shadcn@latest add badge
```

## What Gets Created

```
components/
└── copy-preview/
    ├── tweet-card.tsx
    ├── instagram-caption.tsx
    ├── linkedin-post.tsx
    ├── email-subject.tsx
    └── copy-preview.tsx
```

## Setup Steps

### Step 1: Create `components/copy-preview/tweet-card.tsx`

```typescript
"use client"

import {
  ArrowsClockwise,
  ChatCircle,
  Export,
  Heart,
  ChartBar,
} from "@phosphor-icons/react"
import { useId } from "react"

type TweetCardProps = {
  copy: string
  authorName?: string
  authorHandle?: string
  authorAvatar?: string
  className?: string
}

const CHAR_LIMIT = 280

function renderCopyText(text: string): React.ReactNode[] {
  const id = Math.random().toString(36).slice(2)
  return text.split(/(\s+)/).map((word, i) => {
    const key = `${id}-word-${i}`
    if (/^#\w+/.test(word)) {
      return <span key={key} className="text-sky-500">{word}</span>
    }
    if (/^@\w+/.test(word)) {
      return <span key={key} className="text-sky-500">{word}</span>
    }
    if (/^https?:\/\/\S+/.test(word)) {
      return <span key={key} className="text-sky-500">{word}</span>
    }
    return <span key={key}>{word}</span>
  })
}

function InitialsAvatar({ name, size }: { name: string; size: number }) {
  const initials = name
    .split(" ")
    .map((p) => p[0])
    .join("")
    .slice(0, 2)
    .toUpperCase()

  return (
    <div
      style={{ width: size, height: size }}
      className="flex items-center justify-center rounded-full bg-gradient-to-br from-sky-400 to-blue-600 text-white font-bold shrink-0"
      style2={{ fontSize: size * 0.38 }}
    >
      <span style={{ fontSize: size * 0.38 }}>{initials}</span>
    </div>
  )
}

export function TweetCard({
  copy,
  authorName = "Your Name",
  authorHandle = "@yourhandle",
  authorAvatar,
  className,
}: TweetCardProps) {
  const charCount = copy.length
  const isOver = charCount > CHAR_LIMIT
  const engagementId = useId()

  const engagementItems = [
    { icon: <ChatCircle size={18} />, label: "Reply" },
    { icon: <ArrowsClockwise size={18} />, label: "Repost" },
    { icon: <Heart size={18} />, label: "Like" },
    { icon: <ChartBar size={18} />, label: "Views" },
    { icon: <Export size={18} />, label: "Share" },
  ]

  return (
    <div
      className={[
        "w-[598px] rounded-2xl border border-zinc-200 bg-white p-4 shadow-sm",
        className,
      ]
        .filter(Boolean)
        .join(" ")}
    >
      {/* Header */}
      <div className="flex items-start justify-between">
        <div className="flex items-center gap-3">
          {authorAvatar ? (
            <img
              src={authorAvatar}
              alt={authorName}
              className="h-10 w-10 rounded-full object-cover"
            />
          ) : (
            <InitialsAvatar name={authorName} size={40} />
          )}
          <div>
            <p className="text-sm font-bold leading-tight text-zinc-900">{authorName}</p>
            <p className="text-sm leading-tight text-zinc-500">{authorHandle}</p>
          </div>
        </div>
        {/* X logo */}
        <svg viewBox="0 0 24 24" className="h-5 w-5 fill-zinc-900" aria-hidden="true">
          <path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-4.714-6.231-5.401 6.231H2.766l7.73-8.835L1.254 2.25H8.08l4.259 5.63 5.905-5.63zm-1.161 17.52h1.833L7.084 4.126H5.117z" />
        </svg>
      </div>

      {/* Body */}
      <div className="mt-3 whitespace-pre-wrap text-[15px] leading-relaxed text-zinc-900">
        {renderCopyText(copy)}
      </div>

      {/* Char counter */}
      <div className="mt-3 flex items-center justify-end">
        <span
          className={[
            "text-sm font-medium tabular-nums",
            isOver ? "text-red-500" : "text-green-600",
          ].join(" ")}
        >
          {charCount}/{CHAR_LIMIT}
        </span>
      </div>

      {/* Engagement row */}
      <div className="mt-3 flex items-center justify-between border-t border-zinc-100 pt-3">
        {engagementItems.map((item, i) => {
          const key = `${engagementId}-eng-${i}`
          return (
            <button
              key={key}
              aria-label={item.label}
              className="flex items-center gap-1 text-zinc-400 hover:text-sky-500 transition-colors"
            >
              {item.icon}
            </button>
          )
        })}
      </div>
    </div>
  )
}
```

### Step 2: Create `components/copy-preview/instagram-caption.tsx`

```typescript
"use client"

import { DotsThree, Heart } from "@phosphor-icons/react"
import { useId, useState } from "react"

type InstagramCaptionProps = {
  copy: string
  authorName?: string
  authorHandle?: string
  authorAvatar?: string
  className?: string
}

const TRUNCATE_AT = 125

function renderHashtags(text: string, prefix: string): React.ReactNode[] {
  return text.split(/(\s+)/).map((word, i) => {
    const key = `${prefix}-word-${i}`
    if (/^#\w+/.test(word)) {
      return <span key={key} className="text-sky-500">{word}</span>
    }
    return <span key={key}>{word}</span>
  })
}

function InitialsAvatar({ name, size }: { name: string; size: number }) {
  const initials = name
    .split(" ")
    .map((p) => p[0])
    .join("")
    .slice(0, 2)
    .toUpperCase()
  return (
    <div
      style={{ width: size, height: size }}
      className="flex shrink-0 items-center justify-center rounded-full bg-gradient-to-br from-pink-400 via-red-400 to-yellow-400 font-bold text-white"
    >
      <span style={{ fontSize: size * 0.38 }}>{initials}</span>
    </div>
  )
}

export function InstagramCaption({
  copy,
  authorName = "Your Name",
  authorHandle = "@yourhandle",
  authorAvatar,
  className,
}: InstagramCaptionProps) {
  const [expanded, setExpanded] = useState(false)
  const wordId = useId()
  const isTruncated = copy.length > TRUNCATE_AT
  const displayText = isTruncated && !expanded ? copy.slice(0, TRUNCATE_AT) : copy

  return (
    <div
      className={[
        "w-[400px] overflow-hidden rounded-2xl border border-zinc-200 bg-white shadow-sm",
        className,
      ]
        .filter(Boolean)
        .join(" ")}
    >
      {/* Header */}
      <div className="flex items-center justify-between px-3 py-2.5">
        <div className="flex items-center gap-2.5">
          {authorAvatar ? (
            <img
              src={authorAvatar}
              alt={authorName}
              className="h-8 w-8 rounded-full object-cover ring-2 ring-pink-400"
            />
          ) : (
            <div className="rounded-full p-0.5 bg-gradient-to-br from-pink-400 via-red-400 to-yellow-400">
              <InitialsAvatar name={authorName} size={30} />
            </div>
          )}
          <span className="text-sm font-semibold text-zinc-900">{authorHandle}</span>
        </div>
        <DotsThree size={20} className="text-zinc-500" />
      </div>

      {/* Simulated image placeholder */}
      <div className="aspect-square w-full bg-gradient-to-br from-zinc-200 via-zinc-100 to-zinc-200 flex items-center justify-center">
        <svg viewBox="0 0 24 24" className="h-12 w-12 fill-zinc-300" aria-hidden="true">
          <path d="M21 15.5a3.5 3.5 0 0 1-3.5 3.5h-11A3.5 3.5 0 0 1 3 15.5v-7A3.5 3.5 0 0 1 6.5 5h11A3.5 3.5 0 0 1 21 8.5v7zM8.75 10a2.25 2.25 0 1 0 0-4.5 2.25 2.25 0 0 0 0 4.5zm11.5 5-3.97-3.97a.75.75 0 0 0-1.06 0L11.5 14.75 9.28 12.53a.75.75 0 0 0-1.06 0L3.5 17.25" />
        </svg>
      </div>

      {/* Like row */}
      <div className="flex items-center gap-1 px-3 pt-2.5">
        <Heart size={20} weight="fill" className="text-red-500" />
        <span className="text-sm font-semibold text-zinc-800">1,234 likes</span>
      </div>

      {/* Caption */}
      <div className="px-3 py-2 text-sm text-zinc-800 leading-relaxed">
        <span className="font-semibold">{authorHandle} </span>
        {renderHashtags(displayText, wordId)}
        {isTruncated && !expanded && (
          <>
            {"... "}
            <button
              onClick={() => setExpanded(true)}
              className="text-zinc-500 hover:text-zinc-700 font-medium"
            >
              more
            </button>
          </>
        )}
      </div>

      {/* Comment placeholder */}
      <div className="border-t border-zinc-100 px-3 py-2.5 text-sm text-zinc-400">
        Add a comment...
      </div>
    </div>
  )
}
```

### Step 3: Create `components/copy-preview/linkedin-post.tsx`

```typescript
"use client"

import {
  ArrowsClockwise,
  ChatCircle,
  PaperPlaneTilt,
  ThumbsUp,
} from "@phosphor-icons/react"
import { useId, useState } from "react"

type LinkedInPostProps = {
  copy: string
  authorName?: string
  authorHandle?: string
  authorAvatar?: string
  className?: string
}

const TRUNCATE_AT = 200

function InitialsAvatar({ name, size }: { name: string; size: number }) {
  const initials = name
    .split(" ")
    .map((p) => p[0])
    .join("")
    .slice(0, 2)
    .toUpperCase()
  return (
    <div
      style={{ width: size, height: size }}
      className="flex shrink-0 items-center justify-center rounded-full bg-blue-600 font-bold text-white"
    >
      <span style={{ fontSize: size * 0.38 }}>{initials}</span>
    </div>
  )
}

export function LinkedInPost({
  copy,
  authorName = "Your Name",
  authorHandle = "Your Title",
  authorAvatar,
  className,
}: LinkedInPostProps) {
  const [expanded, setExpanded] = useState(false)
  const actionId = useId()
  const isTruncated = copy.length > TRUNCATE_AT
  const displayText = isTruncated && !expanded ? copy.slice(0, TRUNCATE_AT) : copy

  const actions = [
    { icon: <ThumbsUp size={16} />, label: "Like" },
    { icon: <ChatCircle size={16} />, label: "Comment" },
    { icon: <ArrowsClockwise size={16} />, label: "Repost" },
    { icon: <PaperPlaneTilt size={16} />, label: "Send" },
  ]

  return (
    <div
      className={[
        "w-[552px] rounded-2xl border border-zinc-200 bg-white shadow-sm",
        className,
      ]
        .filter(Boolean)
        .join(" ")}
    >
      {/* Header */}
      <div className="flex items-start justify-between p-4">
        <div className="flex items-start gap-3">
          {authorAvatar ? (
            <img
              src={authorAvatar}
              alt={authorName}
              className="h-12 w-12 rounded-full object-cover"
            />
          ) : (
            <InitialsAvatar name={authorName} size={48} />
          )}
          <div>
            <p className="text-sm font-semibold leading-tight text-zinc-900">{authorName}</p>
            <p className="text-xs leading-tight text-zinc-500">{authorHandle} • 1st</p>
            <p className="mt-0.5 text-xs text-zinc-400">Just now •</p>
          </div>
        </div>
        {/* LinkedIn logo */}
        <svg viewBox="0 0 24 24" className="h-5 w-5 fill-blue-600 shrink-0" aria-hidden="true">
          <path d="M20.447 20.452h-3.554v-5.569c0-1.328-.027-3.037-1.852-3.037-1.853 0-2.136 1.445-2.136 2.939v5.667H9.351V9h3.414v1.561h.046c.477-.9 1.637-1.85 3.37-1.85 3.601 0 4.267 2.37 4.267 5.455v6.286zM5.337 7.433a2.062 2.062 0 0 1-2.063-2.065 2.064 2.064 0 1 1 2.063 2.065zm1.782 13.019H3.555V9h3.564v11.452zM22.225 0H1.771C.792 0 0 .774 0 1.729v20.542C0 23.227.792 24 1.771 24h20.451C23.2 24 24 23.227 24 22.271V1.729C24 .774 23.2 0 22.222 0h.003z" />
        </svg>
      </div>

      {/* Body */}
      <div className="px-4 pb-3 text-sm leading-relaxed text-zinc-800 whitespace-pre-wrap">
        {displayText}
        {isTruncated && !expanded && (
          <>
            {"... "}
            <button
              onClick={() => setExpanded(true)}
              className="font-medium text-zinc-500 hover:text-zinc-800"
            >
              see more
            </button>
          </>
        )}
      </div>

      {/* Reaction count */}
      <div className="flex items-center justify-between border-t border-zinc-100 px-4 py-2 text-xs text-zinc-500">
        <span>24 reactions</span>
        <span>3 comments</span>
      </div>

      {/* Action row */}
      <div className="flex items-center border-t border-zinc-100 px-2 py-1">
        {actions.map((action, i) => {
          const key = `${actionId}-action-${i}`
          return (
            <button
              key={key}
              className="flex flex-1 items-center justify-center gap-1.5 rounded-md py-2 text-xs font-medium text-zinc-500 hover:bg-zinc-50 hover:text-zinc-800 transition-colors"
            >
              {action.icon}
              {action.label}
            </button>
          )
        })}
      </div>
    </div>
  )
}
```

### Step 4: Create `components/copy-preview/email-subject.tsx`

```typescript
"use client"

import { Circle } from "@phosphor-icons/react"
import { useState } from "react"

type EmailSubjectProps = {
  copy: string
  authorName?: string
  authorAvatar?: string
  className?: string
}

const PREVIEW_LENGTH = 50

function InitialsAvatar({ name, size }: { name: string; size: number }) {
  const initials = name
    .split(" ")
    .map((p) => p[0])
    .join("")
    .slice(0, 2)
    .toUpperCase()
  return (
    <div
      style={{ width: size, height: size }}
      className="flex shrink-0 items-center justify-center rounded-full bg-gradient-to-br from-indigo-400 to-purple-500 font-bold text-white"
    >
      <span style={{ fontSize: size * 0.38 }}>{initials}</span>
    </div>
  )
}

function extractSubject(copy: string): string {
  const firstLine = copy.split("\n")[0].trim()
  return firstLine.length > 60 ? firstLine.slice(0, 60) + "…" : firstLine
}

function extractPreview(copy: string): string {
  const text = copy.replace(/\n/g, " ").trim()
  return text.length > PREVIEW_LENGTH ? text.slice(0, PREVIEW_LENGTH) + "…" : text
}

export function EmailSubjectLine({
  copy,
  authorName = "Your Name",
  authorAvatar,
  className,
}: EmailSubjectProps) {
  const [opened, setOpened] = useState(false)
  const subject = extractSubject(copy)
  const preview = extractPreview(copy)

  return (
    <div className={["w-full font-sans", className].filter(Boolean).join(" ")}>
      {/* Inbox row */}
      <div
        className="flex cursor-pointer items-center gap-3 rounded-xl border border-zinc-200 bg-white px-4 py-3 shadow-sm hover:bg-zinc-50 transition-colors"
        onClick={() => setOpened((o) => !o)}
        role="button"
        tabIndex={0}
        onKeyDown={(e) => { if (e.key === "Enter" || e.key === " ") setOpened((o) => !o) }}
        aria-expanded={opened}
      >
        {/* Unread dot */}
        <Circle size={10} weight="fill" className="shrink-0 text-blue-500" />

        {/* Avatar */}
        {authorAvatar ? (
          <img
            src={authorAvatar}
            alt={authorName}
            className="h-9 w-9 rounded-full object-cover shrink-0"
          />
        ) : (
          <InitialsAvatar name={authorName} size={36} />
        )}

        {/* Sender + subject + preview */}
        <div className="min-w-0 flex-1">
          <div className="flex items-baseline gap-2">
            <span className="truncate text-sm font-semibold text-zinc-900">{authorName}</span>
          </div>
          <div className="flex items-baseline gap-1.5 truncate">
            <span className="text-sm font-semibold text-zinc-800 truncate">{subject}</span>
            <span className="text-sm text-zinc-400 truncate shrink">{preview}</span>
          </div>
        </div>

        {/* Timestamp */}
        <span className="shrink-0 text-xs text-zinc-400">9:41 AM</span>
      </div>

      {/* Opened email */}
      {opened && (
        <div className="mt-3 rounded-xl border border-zinc-200 bg-white shadow-sm">
          {/* Email header */}
          <div className="border-b border-zinc-100 px-6 py-4">
            <h1 className="text-xl font-bold text-zinc-900">{subject}</h1>
            <div className="mt-2 flex items-center gap-3">
              {authorAvatar ? (
                <img
                  src={authorAvatar}
                  alt={authorName}
                  className="h-8 w-8 rounded-full object-cover"
                />
              ) : (
                <InitialsAvatar name={authorName} size={32} />
              )}
              <div>
                <p className="text-sm font-semibold text-zinc-800">{authorName}</p>
                <p className="text-xs text-zinc-400">To: me</p>
              </div>
            </div>
          </div>
          {/* Email body */}
          <div className="px-6 py-5">
            <div className="mx-auto max-w-[400px] whitespace-pre-wrap text-sm leading-relaxed text-zinc-700">
              {copy}
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
```

### Step 5: Create `components/copy-preview/copy-preview.tsx`

```typescript
"use client"

import { EmailSubjectLine } from "@/components/copy-preview/email-subject"
import { InstagramCaption } from "@/components/copy-preview/instagram-caption"
import { LinkedInPost } from "@/components/copy-preview/linkedin-post"
import { TweetCard } from "@/components/copy-preview/tweet-card"

export type CopyPlatform = "twitter" | "instagram" | "linkedin" | "email"

export type CopyPreviewProps = {
  platform: CopyPlatform
  copy: string
  authorName?: string
  authorHandle?: string
  authorAvatar?: string
  className?: string
}

const PLATFORM_LABELS: Record<CopyPlatform, string> = {
  twitter: "X / Twitter",
  instagram: "Instagram",
  linkedin: "LinkedIn",
  email: "Email",
}

export function CopyPreview({
  platform,
  copy,
  authorName,
  authorHandle,
  authorAvatar,
  className,
}: CopyPreviewProps) {
  return (
    <div className={["flex flex-col gap-3", className].filter(Boolean).join(" ")}>
      {/* Platform badge */}
      <div className="flex items-center gap-2">
        <span className="rounded-full bg-zinc-100 px-2.5 py-1 text-xs font-semibold tracking-wide text-zinc-600 uppercase">
          {PLATFORM_LABELS[platform]}
        </span>
      </div>

      {/* Platform card */}
      {platform === "twitter" && (
        <TweetCard
          copy={copy}
          authorName={authorName}
          authorHandle={authorHandle}
          authorAvatar={authorAvatar}
        />
      )}
      {platform === "instagram" && (
        <InstagramCaption
          copy={copy}
          authorName={authorName}
          authorHandle={authorHandle}
          authorAvatar={authorAvatar}
        />
      )}
      {platform === "linkedin" && (
        <LinkedInPost
          copy={copy}
          authorName={authorName}
          authorHandle={authorHandle}
          authorAvatar={authorAvatar}
        />
      )}
      {platform === "email" && (
        <EmailSubjectLine
          copy={copy}
          authorName={authorName}
          authorAvatar={authorAvatar}
        />
      )}
    </div>
  )
}
```

## Usage

```typescript
import { CopyPreview } from "@/components/copy-preview/copy-preview"

// Twitter
<CopyPreview
  platform="twitter"
  copy="Just shipped a new feature! Check it out at https://example.com #buildinpublic @nextjs"
  authorName="Jane Doe"
  authorHandle="@janedoe"
/>

// Instagram
<CopyPreview
  platform="instagram"
  copy={"Behind the scenes of our latest launch! 🚀\n\nWe spent 3 months building this and can't wait to hear what you think. Drop your thoughts in the comments below!\n\n#launch #startup #buildinpublic #saas #productdesign #indiemaker"}
  authorHandle="@janedoe"
/>

// LinkedIn
<CopyPreview
  platform="linkedin"
  copy={"After 10 years in enterprise software, I've learned that the best products are built with radical empathy.\n\nHere's what that means in practice..."}
  authorName="Jane Doe"
  authorHandle="Senior Product Manager"
/>

// Email
<CopyPreview
  platform="email"
  copy={"Your trial ends in 3 days\n\nHi there,\n\nWe noticed you haven't tried our AI features yet. Here's a quick walkthrough to get you started before your trial ends.\n\nBest,\nThe Team"}
  authorName="The Team"
/>

// Character counter behavior
<TweetCard copy={"x".repeat(300)} /> // counter shows "300/280" in red
<TweetCard copy="Hello world" />      // counter shows "11/280" in green
```

## Acceptance Criteria

- `<TweetCard copy="Hello world" />` renders a card with character counter showing "11/280" in green
- `<TweetCard copy={"x".repeat(300)} />` renders a card with character counter showing "300/280" in red
- `#hashtags`, `@mentions`, and `https://` links in `TweetCard` are rendered in `text-sky-500`
- `<InstagramCaption copy={"x".repeat(200)} />` truncates at 125 characters and shows a "more" button
- Clicking "more" in `InstagramCaption` expands the full caption
- `<LinkedInPost>` truncates at 200 characters with a "see more" button
- `<EmailSubjectLine>` shows an inbox row; clicking it toggles the opened email view
- The inbox row shows a blue unread dot
- `<CopyPreview platform="twitter" copy="..." />` renders `TweetCard`
- `<CopyPreview platform="instagram" copy="..." />` renders `InstagramCaption`
- `<CopyPreview platform="linkedin" copy="..." />` renders `LinkedInPost`
- `<CopyPreview platform="email" copy="..." />` renders `EmailSubjectLine`
- No `index` used as a React list key anywhere
- `tsc --noEmit` passes with no errors
- `bun run build` succeeds
