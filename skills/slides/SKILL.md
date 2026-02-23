---
name: slides
description: Transform markdown to beautiful Apple-like presentation slides using Marp. Use this skill when the user says "create slides", "make presentation", "markdown to slides", "generate deck", or "create powerpoint".
author: "@mattwoodco"
version: 1.1.0
created: 2026-01-12
dependencies: []
---

# Slides - Markdown to Beautiful Presentations

Transform markdown content into stunning, Apple Keynote-inspired presentation slides using Marp with AI-enhanced content generation.

## Quick Start

```bash
# Install Marp CLI globally
bun add -g @marp-team/marp-cli

# Or install locally in project
bun add @marp-team/marp-cli
```

## What Gets Created

| Skill File | Target Project Path | Description |
|------------|---------------------|-------------|
| `lib/slides.ts` | `src/lib/slides.ts` | Core slides generation library |
| `lib/slides-theme.css` | `src/lib/slides-theme.css` | Apple-inspired Marp theme |
| (embedded) | `src/lib/ai/tools/slides-tool.ts` | AI tool for slide generation |
| (embedded) | `src/app/api/slides/route.ts` | API endpoint for slides |

## Apple-Inspired Theme

The theme features:

- **Typography**: SF Pro-inspired clean sans-serif fonts
- **Colors**: Neutral grays with vibrant accent colors
- **Spacing**: Generous whitespace, elegant margins
- **Layout**: Centered content, minimal visual noise
- **Animations**: Subtle fade transitions

## Installation

```bash
bun add @marp-team/marp-cli puppeteer-core ai zod
```

## Environment Variables

```env
# Optional: Custom Chromium path for PDF/PPTX export
PUPPETEER_EXECUTABLE_PATH=/path/to/chromium
```

## Theme CSS

Create `src/lib/slides-theme.css`:

```css
/* Apple-Inspired Marp Theme */
/* @theme apple */

@import 'default';

:root {
  /* Apple-like color palette */
  --color-background: #ffffff;
  --color-foreground: #1d1d1f;
  --color-muted: #86868b;
  --color-accent: #0071e3;
  --color-accent-light: #147ce5;

  /* Typography */
  --font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Display', 'SF Pro Text', 'Helvetica Neue', Helvetica, Arial, sans-serif;
  --font-mono: 'SF Mono', ui-monospace, SFMono-Regular, 'Cascadia Code', Menlo, monospace;

  /* Sizing */
  --slide-width: 1920px;
  --slide-height: 1080px;
}

section {
  font-family: var(--font-family);
  font-size: 40px;
  font-weight: 400;
  color: var(--color-foreground);
  background: var(--color-background);
  padding: 80px 120px;
  display: flex;
  flex-direction: column;
  justify-content: center;
}

/* Title Slides */
section.title {
  text-align: center;
  justify-content: center;
  align-items: center;
}

section.title h1 {
  font-size: 96px;
  font-weight: 700;
  letter-spacing: -0.02em;
  line-height: 1.1;
  margin-bottom: 24px;
  background: linear-gradient(135deg, #1d1d1f 0%, #424245 100%);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  background-clip: text;
}

section.title h2 {
  font-size: 48px;
  font-weight: 400;
  color: var(--color-muted);
  margin: 0;
}

/* Content Slides */
h1 {
  font-size: 72px;
  font-weight: 700;
  letter-spacing: -0.02em;
  line-height: 1.15;
  margin: 0 0 40px 0;
  color: var(--color-foreground);
}

h2 {
  font-size: 56px;
  font-weight: 600;
  letter-spacing: -0.01em;
  margin: 0 0 32px 0;
  color: var(--color-foreground);
}

h3 {
  font-size: 44px;
  font-weight: 600;
  margin: 0 0 24px 0;
  color: var(--color-muted);
}

p {
  font-size: 36px;
  line-height: 1.6;
  margin: 0 0 24px 0;
  color: var(--color-foreground);
}

/* Lists */
ul, ol {
  margin: 0;
  padding-left: 48px;
}

li {
  font-size: 36px;
  line-height: 1.6;
  margin-bottom: 16px;
  color: var(--color-foreground);
}

li::marker {
  color: var(--color-accent);
}

/* Code */
code {
  font-family: var(--font-mono);
  font-size: 32px;
  background: #f5f5f7;
  border-radius: 8px;
  padding: 4px 12px;
}

pre {
  background: #1d1d1f;
  border-radius: 16px;
  padding: 32px 40px;
  overflow: hidden;
}

pre code {
  background: transparent;
  color: #f5f5f7;
  font-size: 28px;
  line-height: 1.5;
  padding: 0;
}

/* Blockquotes */
blockquote {
  border-left: 6px solid var(--color-accent);
  padding-left: 32px;
  margin: 32px 0;
  font-style: italic;
  color: var(--color-muted);
}

/* Images */
img {
  max-width: 100%;
  border-radius: 16px;
  box-shadow: 0 20px 60px rgba(0, 0, 0, 0.12);
}

/* Links */
a {
  color: var(--color-accent);
  text-decoration: none;
}

a:hover {
  text-decoration: underline;
}

/* Dark Mode */
section.dark {
  background: #1d1d1f;
  color: #f5f5f7;
}

section.dark h1,
section.dark h2,
section.dark p,
section.dark li {
  color: #f5f5f7;
}

section.dark h3 {
  color: #a1a1a6;
}

section.dark code {
  background: #2d2d30;
  color: #f5f5f7;
}

/* Gradient Backgrounds */
section.gradient-blue {
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  color: white;
}

section.gradient-blue h1,
section.gradient-blue h2,
section.gradient-blue p,
section.gradient-blue li {
  color: white;
}

section.gradient-orange {
  background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%);
  color: white;
}

section.gradient-green {
  background: linear-gradient(135deg, #4facfe 0%, #00f2fe 100%);
  color: #1d1d1f;
}

/* Two Column Layout */
section.split {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 80px;
  align-items: center;
}

/* Center Layout */
section.center {
  text-align: center;
  align-items: center;
}

/* Page Numbers */
section::after {
  content: attr(data-marpit-pagination) ' / ' attr(data-marpit-pagination-total);
  position: absolute;
  bottom: 40px;
  right: 60px;
  font-size: 24px;
  color: var(--color-muted);
}

/* Hide pagination on title slides */
section.title::after {
  display: none;
}

/* Transitions */
@keyframes fadeIn {
  from { opacity: 0; transform: translateY(20px); }
  to { opacity: 1; transform: translateY(0); }
}

section > * {
  animation: fadeIn 0.6s ease-out forwards;
}
```

## Slides Library

Create `src/lib/slides.ts`:

```typescript
import { spawn } from "child_process";
import { writeFile, readFile, unlink, mkdir } from "fs/promises";
import { join } from "path";
import { tmpdir } from "os";
import { randomUUID } from "crypto";

type SlideTheme = "apple" | "default" | "gaia" | "uncover";
type ExportFormat = "html" | "pdf" | "pptx" | "png" | "jpeg";

type SlidesConfig = {
  theme?: SlideTheme;
  format?: ExportFormat;
  width?: number;
  height?: number;
  allowLocalFiles?: boolean;
};

type SlidesResult = {
  success: boolean;
  filePath?: string;
  buffer?: Buffer;
  error?: string;
};

const APPLE_THEME_PATH = join(process.cwd(), "src/lib/slides-theme.css");

/**
 * Convert markdown to slides using Marp CLI
 */
export async function convertMarkdownToSlides(
  markdown: string,
  config: SlidesConfig = {}
): Promise<SlidesResult> {
  const {
    theme = "apple",
    format = "html",
    width = 1920,
    height = 1080,
    allowLocalFiles = false,
  } = config;

  const tempDir = join(tmpdir(), "marp-slides");
  const sessionId = randomUUID();
  const inputPath = join(tempDir, `${sessionId}.md`);
  const outputPath = join(tempDir, `${sessionId}.${format}`);

  try {
    // Ensure temp directory exists
    await mkdir(tempDir, { recursive: true });

    // Prepare markdown with frontmatter
    const frontmatter = [
      "---",
      "marp: true",
      theme === "apple" ? `theme: apple` : `theme: ${theme}`,
      "paginate: true",
      `size: ${width}x${height}`,
      "---",
      "",
    ].join("\n");

    const fullMarkdown = frontmatter + markdown;
    await writeFile(inputPath, fullMarkdown, "utf-8");

    // Build Marp CLI arguments
    const args: string[] = [inputPath, "-o", outputPath];

    // Add theme CSS if using custom Apple theme
    if (theme === "apple") {
      args.push("--theme", APPLE_THEME_PATH);
    }

    // Format-specific options
    if (format === "pptx" || format === "pdf") {
      args.push("--allow-local-files");
    }

    if (format === "png" || format === "jpeg") {
      args.push("--images", format);
    }

    if (allowLocalFiles) {
      args.push("--allow-local-files");
    }

    // Execute Marp CLI
    await new Promise<void>((resolve, reject) => {
      const marp = spawn("npx", ["@marp-team/marp-cli", ...args], {
        cwd: process.cwd(),
        shell: true,
      });

      let stderr = "";
      marp.stderr.on("data", (data) => {
        stderr += data.toString();
      });

      marp.on("close", (code) => {
        if (code === 0) {
          resolve();
        } else {
          reject(new Error(`Marp CLI exited with code ${code}: ${stderr}`));
        }
      });

      marp.on("error", reject);
    });

    // Read the output file
    const buffer = await readFile(outputPath);

    // Cleanup input file
    await unlink(inputPath).catch(() => {});

    return {
      success: true,
      filePath: outputPath,
      buffer,
    };
  } catch (error) {
    // Cleanup on error
    await unlink(inputPath).catch(() => {});
    await unlink(outputPath).catch(() => {});

    return {
      success: false,
      error: error instanceof Error ? error.message : "Unknown error",
    };
  }
}

/**
 * Generate slide markdown from content outline using AI
 */
export function createSlideMarkdown(slides: SlideContent[]): string {
  return slides
    .map((slide, index) => {
      const parts: string[] = [];

      // Add slide separator (except for first slide)
      if (index > 0) {
        parts.push("\n---\n");
      }

      // Add class directive if specified
      if (slide.class) {
        parts.push(`<!-- _class: ${slide.class} -->`);
      }

      // Add title
      if (slide.title) {
        const level = slide.titleLevel || 1;
        parts.push(`${"#".repeat(level)} ${slide.title}`);
      }

      // Add subtitle
      if (slide.subtitle) {
        parts.push(`## ${slide.subtitle}`);
      }

      // Add content
      if (slide.content) {
        parts.push(slide.content);
      }

      // Add bullet points
      if (slide.bullets && slide.bullets.length > 0) {
        parts.push(slide.bullets.map((b) => `- ${b}`).join("\n"));
      }

      // Add code block
      if (slide.code) {
        parts.push(`\`\`\`${slide.codeLanguage || ""}\n${slide.code}\n\`\`\``);
      }

      // Add image
      if (slide.image) {
        parts.push(`![${slide.imageAlt || ""}](${slide.image})`);
      }

      // Add speaker notes
      if (slide.notes) {
        parts.push(`\n<!--\n${slide.notes}\n-->`);
      }

      return parts.join("\n\n");
    })
    .join("\n");
}

type SlideContent = {
  title?: string;
  titleLevel?: 1 | 2 | 3;
  subtitle?: string;
  content?: string;
  bullets?: string[];
  code?: string;
  codeLanguage?: string;
  image?: string;
  imageAlt?: string;
  notes?: string;
  class?: "title" | "dark" | "split" | "center" | "gradient-blue" | "gradient-orange" | "gradient-green";
};

export type { SlideTheme, ExportFormat, SlidesConfig, SlidesResult, SlideContent };
```

## AI Tool Integration

Create `src/lib/ai/tools/slides-tool.ts`:

```typescript
import { tool } from "ai";
import { z } from "zod";
import {
  convertMarkdownToSlides,
  createSlideMarkdown,
  type SlideContent,
  type ExportFormat,
} from "@/lib/slides";

type SlidesToolResult =
  | {
      success: true;
      markdown: string;
      message: string;
      exportInfo?: {
        format: ExportFormat;
        filePath?: string;
      };
    }
  | {
      success: false;
      error: string;
    };

const slideSchema = z.object({
  title: z.string().optional().describe("Slide title"),
  titleLevel: z.enum(["1", "2", "3"]).optional().describe("Title heading level"),
  subtitle: z.string().optional().describe("Slide subtitle"),
  content: z.string().optional().describe("Main content paragraph"),
  bullets: z.array(z.string()).optional().describe("Bullet points"),
  code: z.string().optional().describe("Code snippet"),
  codeLanguage: z.string().optional().describe("Programming language for code"),
  image: z.string().optional().describe("Image URL"),
  imageAlt: z.string().optional().describe("Image alt text"),
  notes: z.string().optional().describe("Speaker notes (hidden in presentation)"),
  class: z
    .enum(["title", "dark", "split", "center", "gradient-blue", "gradient-orange", "gradient-green"])
    .optional()
    .describe("Slide style class"),
});

/**
 * Generate presentation slides from structured content
 */
export const generateSlides = tool({
  description:
    "Generate beautiful Apple-styled presentation slides from structured content. Creates Marp markdown that can be exported to HTML, PDF, or PowerPoint.",
  inputSchema: z.object({
    title: z.string().describe("Presentation title"),
    slides: z.array(slideSchema).min(1).max(50).describe("Array of slide content objects"),
    exportFormat: z
      .enum(["html", "pdf", "pptx"])
      .optional()
      .describe("Export format (default: html)"),
  }),
  execute: async ({ title, slides, exportFormat = "html" }): Promise<SlidesToolResult> => {
    try {
      // Create title slide
      const titleSlide: SlideContent = {
        title,
        class: "title",
      };

      // Convert input slides to SlideContent
      const contentSlides: SlideContent[] = slides.map((slide) => ({
        ...slide,
        titleLevel: slide.titleLevel ? (Number.parseInt(slide.titleLevel) as 1 | 2 | 3) : undefined,
      }));

      // Generate markdown
      const markdown = createSlideMarkdown([titleSlide, ...contentSlides]);

      // Export if format specified
      if (exportFormat !== "html") {
        const result = await convertMarkdownToSlides(markdown, {
          theme: "apple",
          format: exportFormat,
        });

        if (!result.success) {
          return {
            success: false,
            error: result.error || "Failed to export slides",
          };
        }

        return {
          success: true,
          markdown,
          message: `Generated ${slides.length + 1} slides and exported to ${exportFormat.toUpperCase()}`,
          exportInfo: {
            format: exportFormat,
            filePath: result.filePath,
          },
        };
      }

      return {
        success: true,
        markdown,
        message: `Generated ${slides.length + 1} slides with Apple-styled theme`,
      };
    } catch (error) {
      return {
        success: false,
        error: error instanceof Error ? error.message : "Unknown error",
      };
    }
  },
});

/**
 * Convert raw markdown to slides
 */
export const convertToSlides = tool({
  description:
    "Convert raw markdown content directly to presentation slides. The markdown should use --- to separate slides.",
  inputSchema: z.object({
    markdown: z.string().describe("Markdown content with --- slide separators"),
    exportFormat: z
      .enum(["html", "pdf", "pptx"])
      .optional()
      .describe("Export format (default: html)"),
  }),
  execute: async ({ markdown, exportFormat = "html" }): Promise<SlidesToolResult> => {
    try {
      const result = await convertMarkdownToSlides(markdown, {
        theme: "apple",
        format: exportFormat,
      });

      if (!result.success) {
        return {
          success: false,
          error: result.error || "Failed to convert slides",
        };
      }

      const slideCount = (markdown.match(/^---$/gm) || []).length + 1;

      return {
        success: true,
        markdown,
        message: `Converted ${slideCount} slides to ${exportFormat.toUpperCase()}`,
        exportInfo: {
          format: exportFormat,
          filePath: result.filePath,
        },
      };
    } catch (error) {
      return {
        success: false,
        error: error instanceof Error ? error.message : "Unknown error",
      };
    }
  },
});

export const slidesTools = {
  generateSlides,
  convertToSlides,
};
```

## API Route

Create `src/app/api/slides/route.ts`:

```typescript
import { NextRequest, NextResponse } from "next/server";
import { convertMarkdownToSlides, type ExportFormat } from "@/lib/slides";

export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const { markdown, format = "html" } = body as {
      markdown: string;
      format?: ExportFormat;
    };

    if (!markdown) {
      return NextResponse.json(
        { error: "Markdown content is required" },
        { status: 400 }
      );
    }

    const result = await convertMarkdownToSlides(markdown, {
      theme: "apple",
      format,
    });

    if (!result.success) {
      return NextResponse.json(
        { error: result.error },
        { status: 500 }
      );
    }

    // Return file as download
    const contentTypes: Record<ExportFormat, string> = {
      html: "text/html",
      pdf: "application/pdf",
      pptx: "application/vnd.openxmlformats-officedocument.presentationml.presentation",
      png: "image/png",
      jpeg: "image/jpeg",
    };

    const extensions: Record<ExportFormat, string> = {
      html: "html",
      pdf: "pdf",
      pptx: "pptx",
      png: "png",
      jpeg: "jpg",
    };

    return new NextResponse(result.buffer ? new Uint8Array(result.buffer) : null, {
      headers: {
        "Content-Type": contentTypes[format],
        "Content-Disposition": `attachment; filename="presentation.${extensions[format]}"`,
      },
    });
  } catch (error) {
    return NextResponse.json(
      { error: error instanceof Error ? error.message : "Unknown error" },
      { status: 500 }
    );
  }
}
```

## Usage Examples

### Basic Slide Deck

```markdown
---
marp: true
theme: apple
paginate: true
---

<!-- _class: title -->

# Product Launch 2026

## Introducing the Future

---

# Key Features

- Lightning-fast performance
- Beautiful, intuitive design
- Seamless integration
- Enterprise-grade security

---

<!-- _class: dark -->

# The Numbers

- 10M+ active users
- 99.99% uptime
- 4.9 star rating

---

<!-- _class: center -->

# Thank You

Questions?
```

### Using the AI Tool

```typescript
const result = await generateSlides.execute({
  title: "Q4 Results",
  slides: [
    {
      title: "Revenue Growth",
      bullets: ["45% YoY increase", "$2.3B total revenue", "All regions profitable"],
      class: "dark",
    },
    {
      title: "Product Highlights",
      content: "Our flagship product exceeded all expectations.",
      image: "https://example.com/chart.png",
    },
    {
      title: "Looking Ahead",
      bullets: ["Expand to 5 new markets", "Launch 3 new products", "Double engineering team"],
      class: "gradient-blue",
    },
  ],
  exportFormat: "pptx",
});
```

## Testing

```bash
# Preview slides in browser
bunx @marp-team/marp-cli slides.md --preview

# Export to PDF
bunx @marp-team/marp-cli slides.md -o slides.pdf

# Export to PowerPoint
bunx @marp-team/marp-cli slides.md -o slides.pptx

# Export with custom theme
bunx @marp-team/marp-cli slides.md --theme src/lib/slides-theme.css -o slides.html
```

## Acceptance Criteria

- [ ] Marp CLI installed and working
- [ ] Apple theme CSS renders correctly
- [ ] HTML export works
- [ ] PDF export works
- [ ] PPTX export works
- [ ] AI tool generates valid markdown
- [ ] API endpoint returns correct content types
- [ ] Slides display with proper typography
- [ ] Dark mode slides work
- [ ] Gradient backgrounds render

## Troubleshooting

### PDF/PPTX Export Fails

Marp requires Chromium for PDF/PPTX export:

```bash
# Install Chromium for Puppeteer
bunx puppeteer browsers install chrome

# Or set custom path
PUPPETEER_EXECUTABLE_PATH=/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome bunx @marp-team/marp-cli slides.md -o slides.pdf
```

### Theme Not Found

Ensure the theme CSS file exists and path is correct:

```bash
ls -la src/lib/slides-theme.css
```

### Fonts Not Rendering

The theme uses system fonts. For custom fonts:

```css
@font-face {
  font-family: 'Custom Font';
  src: url('./fonts/custom.woff2') format('woff2');
}
```

## Resources

- [Marp Official Documentation](https://marp.app/)
- [Marp CLI GitHub](https://github.com/marp-team/marp-cli)
- [Marpit Framework](https://marpit.marp.app/)
- [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
