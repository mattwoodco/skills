# RSS Debug Page Testing Reference

## Test Page URL

```
/debug/rss
```

## Expected Elements

### Header Section
- **H1**: "RSS Feed Debug"
- **Description**: "Preview and validate your RSS, Atom, and JSON feeds"

### Feed URLs Section
- RSS 2.0 link with type `application/rss+xml`
- Atom link with type `application/atom+xml`
- JSON Feed link with type `application/feed+json`
- View buttons (open in new tab)
- Copy buttons (copy URL to clipboard)

### Feed Statistics Section
- Total Items count
- Latest Post date
- With Images count
- With Authors count

### Recent Items Section
- Up to 5 recent feed items
- Each item shows:
  - Title
  - Description (truncated to 150 chars)
  - Published date
  - Author name (if available)
  - Categories (if available)

### Feed Previews Section
- RSS 2.0 Preview with XML content
- Atom Preview with XML content
- JSON Feed Preview with formatted JSON
- Expand/Collapse buttons for each preview

### Validation Section
- Link to W3C RSS Validator
- Link to W3C Atom Validator

### Integration Section
- Code example for feed discovery metadata
- Subscribe link examples

## Playwright Test Selectors

```typescript
// Headers
page.getByRole("heading", { name: /RSS Feed Debug/i })
page.getByText("Feed URLs")
page.getByText("Feed Statistics")
page.getByText("Recent Items")

// Feed types
page.getByText("RSS 2.0")
page.getByText("Atom")
page.getByText("JSON Feed")

// Statistics
page.getByText("Total Items")
page.getByText("Latest Post")

// Actions
page.getByRole("button", { name: "Copy" })
page.getByRole("button", { name: "Expand" })
page.getByRole("link", { name: /View/i })
page.getByRole("link", { name: /Validate RSS/i })
page.getByRole("link", { name: /Validate Atom/i })

// Previews
page.getByText("RSS 2.0 Preview")
page.getByText("Atom Preview")
page.getByText("JSON Feed Preview")
```

## Feed Route Endpoints

| Endpoint | Content-Type | Format |
|----------|--------------|--------|
| `/feed.xml` | `application/rss+xml` | RSS 2.0 |
| `/feed.atom` | `application/atom+xml` | Atom 1.0 |
| `/feed.json` | `application/feed+json` | JSON Feed 1.1 |

## Expected Response Structure

### RSS 2.0
```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0">
  <channel>
    <title>Site Title</title>
    <link>https://example.com</link>
    <description>Site description</description>
    <item>
      <title>Post Title</title>
      <link>https://example.com/blog/post-slug</link>
      <guid>https://example.com/blog/post-slug</guid>
      <pubDate>Mon, 12 Jan 2026 00:00:00 GMT</pubDate>
      <description>Post excerpt</description>
    </item>
  </channel>
</rss>
```

### Atom
```xml
<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <id>https://example.com/feed.atom</id>
  <title>Site Title</title>
  <updated>2026-01-12T00:00:00Z</updated>
  <entry>
    <id>https://example.com/blog/post-slug</id>
    <title>Post Title</title>
    <updated>2026-01-12T00:00:00Z</updated>
    <link href="https://example.com/blog/post-slug"/>
  </entry>
</feed>
```

### JSON Feed
```json
{
  "version": "https://jsonfeed.org/version/1.1",
  "title": "Site Title",
  "home_page_url": "https://example.com",
  "feed_url": "https://example.com/feed.json",
  "items": [
    {
      "id": "https://example.com/blog/post-slug",
      "url": "https://example.com/blog/post-slug",
      "title": "Post Title",
      "date_published": "2026-01-12T00:00:00.000Z"
    }
  ]
}
```

## Running Tests

```bash
# Run all RSS tests
bunx playwright test e2e/specs/rss.spec.ts

# Run in headed mode
bunx playwright test e2e/specs/rss.spec.ts --headed

# Run specific test
bunx playwright test -g "RSS 2.0 Feed"

# Debug mode
bunx playwright test e2e/specs/rss.spec.ts --debug
```

## Common Issues

1. **Empty feeds**: Check that Payload CMS has published posts
2. **Invalid XML**: Ensure content doesn't have unescaped characters
3. **Missing metadata**: Add `alternates` to layout.tsx
4. **CORS errors**: Debug page uses client-side fetch, should work on same origin
