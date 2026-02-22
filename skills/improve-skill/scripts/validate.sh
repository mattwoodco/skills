#!/usr/bin/env bash

################################################################################
# validate.sh - Multi-tier validation script for polish-skill sandbox
#
# Runs validation checks in order of strictness:
#   Tier 1: TypeScript compilation (tsc --noEmit)
#   Tier 2: Linting (biome or eslint)
#   Tier 3: Build (if build script exists)
#   Tier 4: Browser validation (TODO - documented but not implemented)
#
# Exit codes:
#   0 - All validations passed
#   1 - Validation errors found
#   2 - Invalid usage or preconditions not met
#
# Output format:
#   JSON array of error objects to STDOUT
#   Progress messages to STDERR
#
# Usage:
#   cd sandbox && ../validate.sh
#   OR
#   ./validate.sh /path/to/sandbox
################################################################################

set -euo pipefail

# Colors for stderr output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Determine sandbox directory
if [ $# -eq 1 ]; then
  SANDBOX_DIR="$1"
elif [ -f "package.json" ] || [ -f "bun.lockb" ] || [ -f "bun.lock" ] || [ -f "package-lock.json" ]; then
  # We're already in a project directory (likely the sandbox)
  SANDBOX_DIR="."
else
  echo -e "${RED}Error: Must run from sandbox directory or provide sandbox path${NC}" >&2
  echo "Usage: $0 [sandbox_directory]" >&2
  exit 2
fi

cd "$SANDBOX_DIR"

# Initialize errors array
ERRORS_JSON="[]"

# Helper function to add error to JSON array
add_error() {
  local source="$1"
  local file="$2"
  local line="$3"
  local message="$4"

  # Escape JSON special characters in message
  message=$(echo "$message" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed 's/	/\\t/g')

  local error_obj
  error_obj=$(cat <<EOF
{
  "source": "$source",
  "file": "$file",
  "line": $line,
  "message": "$message"
}
EOF
)

  # Append to errors array
  if [ "$ERRORS_JSON" = "[]" ]; then
    ERRORS_JSON="[$error_obj]"
  else
    ERRORS_JSON="${ERRORS_JSON%]}, $error_obj]"
  fi
}

# Helper function to check if command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Helper function to check if npm script exists
npm_script_exists() {
  local script_name="$1"
  if [ -f "package.json" ]; then
    node -e "var p=JSON.parse(require(\"fs\").readFileSync(\"package.json\",\"utf8\")); process.stdout.write(String(p.scripts && p.scripts[\"$script_name\"] !== undefined))" 2>/dev/null || echo "false"
  else
    echo "false"
  fi
}

# Detect package manager
if [ -f "bun.lockb" ]; then
  PKG_MANAGER="bun"
  PKG_EXEC="bunx"
elif [ -f "package-lock.json" ]; then
  PKG_MANAGER="npm"
  PKG_EXEC="npx"
elif [ -f "yarn.lock" ]; then
  PKG_MANAGER="yarn"
  PKG_EXEC="yarn dlx"
elif [ -f "pnpm-lock.yaml" ]; then
  PKG_MANAGER="pnpm"
  PKG_EXEC="pnpm dlx"
else
  PKG_MANAGER="npm"
  PKG_EXEC="npx"
fi

echo -e "${BLUE}=== Skill Polish Validation ===${NC}" >&2
echo -e "${BLUE}Package manager: $PKG_MANAGER${NC}" >&2
echo "" >&2

################################################################################
# TIER 1: TypeScript Compilation
################################################################################

echo -e "${YELLOW}[Tier 1] Running TypeScript compilation...${NC}" >&2

# Check if TypeScript is configured
if [ -f "tsconfig.json" ]; then
  # Create temp file for tsc output
  TSC_OUTPUT=$(mktemp)

  if $PKG_EXEC tsc --noEmit 2>&1 | tee "$TSC_OUTPUT"; then
    echo -e "${GREEN}✓ TypeScript compilation passed${NC}" >&2
  else
    echo -e "${RED}✗ TypeScript compilation failed${NC}" >&2

    # Parse tsc errors
    # Format: path/to/file.ts(line,col): error TS####: message
    local tsc_re1='^([^(]+)\(([0-9]+),([0-9]+)\):\ (.+)$'
    local tsc_re2='^([^(]+)\(([0-9]+)\):\ (.+)$'
    while IFS= read -r line; do
      if [[ "$line" =~ $tsc_re1 ]]; then
        file="${BASH_REMATCH[1]}"
        line_num="${BASH_REMATCH[2]}"
        msg="${BASH_REMATCH[4]}"
        add_error "tsc" "$file" "$line_num" "$msg"
      elif [[ "$line" =~ $tsc_re2 ]]; then
        # Alternative format without column
        file="${BASH_REMATCH[1]}"
        line_num="${BASH_REMATCH[2]}"
        msg="${BASH_REMATCH[3]}"
        add_error "tsc" "$file" "$line_num" "$msg"
      fi
    done < "$TSC_OUTPUT"
  fi

  rm -f "$TSC_OUTPUT"
else
  echo -e "${YELLOW}⊘ No tsconfig.json found, skipping TypeScript validation${NC}" >&2
fi

echo "" >&2

################################################################################
# TIER 2: Linting
################################################################################

echo -e "${YELLOW}[Tier 2] Running linting...${NC}" >&2

# Try biome first (preferred)
if [ -f "biome.json" ] || [ -f "biome.jsonc" ]; then
  BIOME_OUTPUT=$(mktemp)

  if $PKG_EXEC biome check . --reporter=json 2>&1 > "$BIOME_OUTPUT"; then
    echo -e "${GREEN}✓ Biome linting passed${NC}" >&2
  else
    echo -e "${RED}✗ Biome linting failed${NC}" >&2

    # Parse biome JSON output
    if command_exists jq; then
      jq -r ".diagnostics[]? | \"\\(.location.path // \"unknown\"):\\(.location.span.start // 0):\\(.message)\"" "$BIOME_OUTPUT" 2>/dev/null | while IFS=: read -r file line msg; do
        add_error "biome" "$file" "${line:-0}" "$msg"
      done
    else
      # Fallback: just capture raw output as a single error
      if [ -s "$BIOME_OUTPUT" ]; then
        add_error "biome" "." "0" "Linting errors found (install jq for detailed parsing)"
      fi
    fi
  fi

  rm -f "$BIOME_OUTPUT"

# Fall back to eslint
elif [ -f ".eslintrc" ] || [ -f ".eslintrc.js" ] || [ -f ".eslintrc.json" ] || [ -f "eslint.config.js" ]; then
  ESLINT_OUTPUT=$(mktemp)

  if $PKG_EXEC eslint . --format json 2>&1 > "$ESLINT_OUTPUT"; then
    echo -e "${GREEN}✓ ESLint passed${NC}" >&2
  else
    echo -e "${RED}✗ ESLint failed${NC}" >&2

    # Parse eslint JSON output
    if command_exists jq; then
      jq -r ".[]?.messages[]? | \"\\(.filePath // \"unknown\"):\\(.line // 0):\\(.message)\"" "$ESLINT_OUTPUT" 2>/dev/null | while IFS=: read -r file line msg; do
        add_error "eslint" "$file" "${line:-0}" "$msg"
      done
    else
      # Fallback
      if [ -s "$ESLINT_OUTPUT" ]; then
        add_error "eslint" "." "0" "Linting errors found (install jq for detailed parsing)"
      fi
    fi
  fi

  rm -f "$ESLINT_OUTPUT"

else
  echo -e "${YELLOW}⊘ No linter configuration found, skipping lint validation${NC}" >&2
fi

echo "" >&2

################################################################################
# TIER 3: Build
################################################################################

echo -e "${YELLOW}[Tier 3] Running build...${NC}" >&2

# Check if build script exists
if [ "$(npm_script_exists 'build')" = "true" ]; then
  BUILD_OUTPUT=$(mktemp)

  if $PKG_MANAGER run build 2>&1 | tee "$BUILD_OUTPUT"; then
    echo -e "${GREEN}✓ Build passed${NC}" >&2
  else
    echo -e "${RED}✗ Build failed${NC}" >&2

    # Parse build errors (common patterns)
    local build_re1='\./(.*):([0-9]+):([0-9]+)\ -\ (.+)$'
    local build_re2='[Ee]rror.*in\ ([^\ ]+\.(ts|tsx|js|jsx))'
    local build_re3='Module\ not\ found:\ (.+)$'
    while IFS= read -r line; do
      # Next.js/Webpack style: ./path/to/file.ts:line:col - error message
      if [[ "$line" =~ $build_re1 ]]; then
        file="${BASH_REMATCH[1]}"
        line_num="${BASH_REMATCH[2]}"
        msg="${BASH_REMATCH[4]}"
        add_error "build" "$file" "$line_num" "$msg"
      # Generic error pattern: error in path/to/file.ts
      elif [[ "$line" =~ $build_re2 ]]; then
        file="${BASH_REMATCH[1]}"
        add_error "build" "$file" "0" "$line"
      # Module not found
      elif [[ "$line" =~ $build_re3 ]]; then
        msg="${BASH_REMATCH[1]}"
        add_error "build" "." "0" "Module not found: $msg"
      fi
    done < "$BUILD_OUTPUT"

    # If no specific errors were parsed, add a generic one
    if [ "$ERRORS_JSON" = "[]" ] && [ -s "$BUILD_OUTPUT" ]; then
      add_error "build" "." "0" "Build failed with unknown errors"
    fi
  fi

  rm -f "$BUILD_OUTPUT"
else
  echo -e "${YELLOW}⊘ No build script found, skipping build validation${NC}" >&2
fi

echo "" >&2

################################################################################
# TIER 4: Browser Validation
################################################################################

echo -e "${YELLOW}[Tier 4] Browser validation...${NC}" >&2
echo -e "${BLUE}TODO: Browser validation not yet automated in this script${NC}" >&2
echo -e "${BLUE}Use playwright-cli (open, snapshot, console, screenshot, click) manually:${NC}" >&2
echo -e "${BLUE}  playwright-cli runs via Bash — no MCP tools needed${NC}" >&2
echo -e "${BLUE}  - playwright-cli open http://localhost:3000/<route>${NC}" >&2
echo -e "${BLUE}  - playwright-cli snapshot${NC}" >&2
echo -e "${BLUE}  - playwright-cli console${NC}" >&2
echo -e "${BLUE}  - playwright-cli screenshot --output screenshots/<name>.png${NC}" >&2

echo "" >&2

################################################################################
# Output Results
################################################################################

# Pretty-print errors to stderr
if [ "$ERRORS_JSON" != "[]" ]; then
  echo -e "${RED}=== Validation Failed ===${NC}" >&2
  echo "" >&2

  if command_exists jq; then
    echo "$ERRORS_JSON" | jq -r ".[] | \"[\\(.source)] \\(.file):\\(.line)\\n  \\(.message)\\n\"" >&2
  else
    echo "Errors found (install jq for pretty formatting):" >&2
    echo "$ERRORS_JSON" >&2
  fi

  # Output JSON to stdout
  echo "$ERRORS_JSON"

  exit 1
else
  echo -e "${GREEN}=== All Validations Passed ===${NC}" >&2

  # Output empty array to stdout
  echo "[]"

  exit 0
fi
