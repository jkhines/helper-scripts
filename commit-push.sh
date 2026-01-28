#!/bin/bash

# commit-push.sh
# Automatically commits code changes following Conventional Commits v1.0.0
# and validates branch naming before pushing to remote

set -euo pipefail

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Function to print colored output
info() {
    echo -e "${GREEN}ℹ${NC} $1"
}

warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1"
}

# Step 1: Check Git Status
info "Checking git status..."
GIT_STATUS=$(git status --porcelain)
if [ -z "$GIT_STATUS" ]; then
    info "No changes to commit."
    exit 0
fi

# Step 2: Validate Current Branch
CURRENT_BRANCH=$(git branch --show-current)
info "Current branch: $CURRENT_BRANCH"

# Valid branch types
VALID_TYPES=("feature" "feat" "bugfix" "fix" "hotfix" "release" "chore" "docs" "refactor" "test" "perf" "ci")
MAIN_BRANCHES=("main" "master" "develop")

# Check if branch is a main branch
IS_MAIN_BRANCH=false
for main_branch in "${MAIN_BRANCHES[@]}"; do
    if [ "$CURRENT_BRANCH" = "$main_branch" ]; then
        IS_MAIN_BRANCH=true
        break
    fi
done

# Check branch naming convention
if [ "$IS_MAIN_BRANCH" = false ]; then
    BRANCH_VALID=false
    for type in "${VALID_TYPES[@]}"; do
        if [[ "$CURRENT_BRANCH" =~ ^${type}/ ]]; then
            BRANCH_VALID=true
            break
        fi
    done
    
    if [ "$BRANCH_VALID" = false ]; then
        warn "Branch '$CURRENT_BRANCH' does not follow conventional naming. Proceeding anyway."
    fi
fi

# Step 3: Analyze Changes
info "Analyzing changes..."

# Get list of changed files
CHANGED_FILES=$(git diff --name-only HEAD)
STAGED_FILES=$(git diff --cached --name-only)

# Combine and get unique files
ALL_CHANGED=$(echo -e "$CHANGED_FILES\n$STAGED_FILES" | sort -u)

# Determine commit type based on changes
COMMIT_TYPE=""
COMMIT_SCOPE=""
BREAKING_CHANGE=false

# Check for different types of changes
HAS_NEW_FILES=false
HAS_DELETED_FILES=false
HAS_MODIFIED_FILES=false
HAS_DOCS=false
HAS_TESTS=false
HAS_CI=false
HAS_BUILD=false
HAS_STYLE=false

for file in $ALL_CHANGED; do
    # Check if file is new
    if git diff --cached --diff-filter=A --name-only | grep -q "^$file$" || \
       ! git ls-files --error-unmatch "$file" &>/dev/null; then
        HAS_NEW_FILES=true
    fi
    
    # Check if file is deleted
    if git diff --cached --diff-filter=D --name-only | grep -q "^$file$" || \
       git diff --diff-filter=D --name-only | grep -q "^$file$"; then
        HAS_DELETED_FILES=true
    fi
    
    # Check file type
    if [[ "$file" =~ \.(md|txt|rst|adoc)$ ]] || [[ "$file" == "README"* ]] || [[ "$file" == "CHANGELOG"* ]]; then
        HAS_DOCS=true
    elif [[ "$file" =~ (test|spec|__tests__) ]] || [[ "$file" =~ \.(test|spec)\.(js|ts|py|rb|java)$ ]]; then
        HAS_TESTS=true
    elif [[ "$file" =~ (\.github|\.gitlab|\.circleci|\.travis|Jenkinsfile|\.gitlab-ci|azure-pipelines) ]]; then
        HAS_CI=true
    elif [[ "$file" =~ (package\.json|package-lock|yarn\.lock|requirements\.txt|Pipfile|poetry\.lock|Cargo\.toml|go\.mod|build\.gradle|pom\.xml|Makefile|CMakeLists\.txt) ]]; then
        HAS_BUILD=true
    fi
done

# Check for style-only changes (whitespace, formatting)
STYLE_ONLY=true
for file in $ALL_CHANGED; do
    if git diff "$file" | grep -q "^[+-][^+-]" && ! git diff "$file" | grep -q "^[+-].*[^[:space:]]"; then
        continue
    fi
    # Check if diff has actual content changes
    if git diff "$file" | grep -E "^[+-]" | grep -vE "^[+-]{3}" | grep -qE "[^[:space:]]"; then
        STYLE_ONLY=false
        break
    fi
done

# Check for breaking changes
# Look for removed functions, changed signatures, removed exports, etc.
BREAKING_INDICATORS=(
    "BREAKING"
    "remove"
    "delete"
    "deprecate"
    "breaking"
)

for file in $ALL_CHANGED; do
    if [ -f "$file" ]; then
        # Check git diff for breaking change indicators
        DIFF_CONTENT=$(git diff "$file" 2>/dev/null || git diff --cached "$file" 2>/dev/null || echo "")
        for indicator in "${BREAKING_INDICATORS[@]}"; do
            if echo "$DIFF_CONTENT" | grep -qi "$indicator"; then
                # Check if it's in a meaningful context (not just in comments)
                if echo "$DIFF_CONTENT" | grep -qiE "(function|def|class|export|public|api|interface).*$indicator|$indicator.*(function|def|class|export|public|api|interface)"; then
                    BREAKING_CHANGE=true
                    break 2
                fi
            fi
        done
        
        # Check for removed exports/functions
        if echo "$DIFF_CONTENT" | grep -qE "^-[[:space:]]*(export|function|def|class|public)"; then
            BREAKING_CHANGE=true
            break
        fi
    fi
done

# Check for feature additions in modified files
HAS_FEATURE_ADDITIONS=false
for file in $ALL_CHANGED; do
    DIFF_CONTENT=$(git diff "$file" 2>/dev/null || git diff --cached "$file" 2>/dev/null || echo "")
    # Look for additions that indicate new features (support, enable, add functionality)
    if echo "$DIFF_CONTENT" | grep -qiE "^\+.*(support|enable|add|implement|introduce|allow).*[^/]"; then
        # Make sure it's not just a comment or string
        if ! echo "$DIFF_CONTENT" | grep -qiE "^\+.*#.*(support|enable|add)"; then
            HAS_FEATURE_ADDITIONS=true
            break
        fi
    fi
done

# Determine commit type
if [ "$HAS_CI" = true ]; then
    COMMIT_TYPE="ci"
elif [ "$HAS_BUILD" = true ]; then
    COMMIT_TYPE="build"
elif [ "$HAS_TESTS" = true ] && [ "$HAS_NEW_FILES" = false ] && [ "$HAS_DELETED_FILES" = false ]; then
    COMMIT_TYPE="test"
elif [ "$HAS_DOCS" = true ] && [ "$(echo "$ALL_CHANGED" | wc -l)" -eq 1 ]; then
    # Only docs changed
    COMMIT_TYPE="docs"
elif [ "$STYLE_ONLY" = true ]; then
    COMMIT_TYPE="style"
elif [ "$HAS_DELETED_FILES" = true ] || [ "$BREAKING_CHANGE" = true ]; then
    # Check if it's a feature removal (breaking) or bug fix
    if [ "$BREAKING_CHANGE" = true ]; then
        COMMIT_TYPE="feat"
    else
        COMMIT_TYPE="fix"
    fi
elif [ "$HAS_NEW_FILES" = true ] || [ "$HAS_FEATURE_ADDITIONS" = true ]; then
    COMMIT_TYPE="feat"
else
    # Default: check if it's a refactor or fix
    # Look at the diff to determine if it's fixing something or refactoring
    HAS_BUG_FIX_KEYWORDS=false
    for file in $ALL_CHANGED; do
        DIFF_CONTENT=$(git diff "$file" 2>/dev/null || git diff --cached "$file" 2>/dev/null || echo "")
        if echo "$DIFF_CONTENT" | grep -qiE "(fix|bug|error|issue|resolve|correct)"; then
            HAS_BUG_FIX_KEYWORDS=true
            break
        fi
    done
    
    if [ "$HAS_BUG_FIX_KEYWORDS" = true ]; then
        COMMIT_TYPE="fix"
    else
        COMMIT_TYPE="refactor"
    fi
fi

# Determine scope from file paths
if [ -n "$ALL_CHANGED" ]; then
    # Get the most common directory prefix
    DIRS=$(echo "$ALL_CHANGED" | sed 's|/[^/]*$||' | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')
    if [ -n "$DIRS" ] && [ "$DIRS" != "." ]; then
        # Use the directory name as scope, but clean it up
        COMMIT_SCOPE=$(basename "$DIRS")
        # Remove leading dot but keep the rest
        COMMIT_SCOPE=$(echo "$COMMIT_SCOPE" | sed 's/^\.//')
        # Handle special cases
        if [ "$COMMIT_SCOPE" = "githooks" ]; then
            COMMIT_SCOPE="hooks"
        fi
    fi
fi

# Step 4: Generate Commit Message
info "Generating commit message..."

# Generate description from changed files and content
DESCRIPTION=""

# Try to generate a smart description from diff content
generate_description() {
    local type=$1
    local desc=""
    
    # Analyze diff content for common patterns
    for file in $ALL_CHANGED; do
        DIFF_CONTENT=$(git diff "$file" 2>/dev/null || git diff --cached "$file" 2>/dev/null || echo "")
        
        if [ "$type" = "feat" ]; then
            # Look for "add", "support", "enable", "implement"
            if echo "$DIFF_CONTENT" | grep -qiE "\+.*(add|support|enable|implement|introduce)"; then
                # Extract key phrases
                if echo "$DIFF_CONTENT" | grep -qi "support.*claude\|claude.*support"; then
                    desc="add support for claude agent"
                elif echo "$DIFF_CONTENT" | grep -qi "support.*multiple\|multiple.*agent"; then
                    desc="add support for multiple agents"
                elif echo "$DIFF_CONTENT" | grep -qi "add.*feature\|new.*feature"; then
                    desc="add new feature"
                elif echo "$DIFF_CONTENT" | grep -qi "enable\|implement"; then
                    KEYWORD=$(echo "$DIFF_CONTENT" | grep -iE "\+.*(enable|implement)" | head -1 | sed 's/.*\(enable\|implement\)[[:space:]]*\([^[:space:]]*\).*/\2/' | tr '[:upper:]' '[:lower:]' | head -c 30)
                    if [ -n "$KEYWORD" ]; then
                        desc="add $KEYWORD"
                    else
                        desc="add new functionality"
                    fi
                fi
            fi
            [ -n "$desc" ] && break
        elif [ "$type" = "fix" ]; then
            # Look for bug fix keywords
            if echo "$DIFF_CONTENT" | grep -qiE "(fix|resolve|correct|repair|bug)"; then
                ISSUE=$(echo "$DIFF_CONTENT" | grep -iE "(fix|resolve|correct)" | head -1 | sed 's/.*\(fix\|resolve\|correct\)[[:space:]]*\([^[:space:]]*\).*/\2/' | tr '[:upper:]' '[:lower:]' | head -c 40)
                if [ -n "$ISSUE" ] && [ ${#ISSUE} -gt 3 ]; then
                    desc="fix $ISSUE"
                else
                    desc="fix bug"
                fi
            fi
            [ -n "$desc" ] && break
        elif [ "$type" = "refactor" ]; then
            if echo "$DIFF_CONTENT" | grep -qiE "(refactor|restructure|simplify|reorganize)"; then
                AREA=$(echo "$DIFF_CONTENT" | grep -iE "(refactor|restructure|simplify)" | head -1 | sed 's/.*\(refactor\|restructure\|simplify\)[[:space:]]*\([^[:space:]]*\).*/\2/' | tr '[:upper:]' '[:lower:]' | head -c 30)
                if [ -n "$AREA" ] && [ ${#AREA} -gt 3 ]; then
                    desc="refactor $AREA"
                else
                    desc="refactor code"
                fi
            fi
            [ -n "$desc" ] && break
        fi
    done
    
    echo "$desc"
}

# Generate description based on type
if [ "$COMMIT_TYPE" = "feat" ]; then
    DESCRIPTION=$(generate_description "feat")
    if [ -z "$DESCRIPTION" ]; then
        if [ "$HAS_NEW_FILES" = true ]; then
            NEW_FILE=$(echo "$ALL_CHANGED" | head -1)
            FILENAME=$(basename "$NEW_FILE" | sed 's/\.[^.]*$//' | tr '[:upper:]' '[:lower:]' | sed 's/_/ /g' | sed 's/-/ /g')
            DESCRIPTION="add $(echo "$FILENAME" | awk '{print $1}')"
        else
            DESCRIPTION="add new functionality"
        fi
    fi
elif [ "$COMMIT_TYPE" = "fix" ]; then
    DESCRIPTION=$(generate_description "fix")
    [ -z "$DESCRIPTION" ] && DESCRIPTION="fix issue"
elif [ "$COMMIT_TYPE" = "docs" ]; then
    DESCRIPTION="update documentation"
elif [ "$COMMIT_TYPE" = "style" ]; then
    DESCRIPTION="format code"
elif [ "$COMMIT_TYPE" = "refactor" ]; then
    DESCRIPTION=$(generate_description "refactor")
    [ -z "$DESCRIPTION" ] && DESCRIPTION="refactor code"
elif [ "$COMMIT_TYPE" = "perf" ]; then
    DESCRIPTION="improve performance"
elif [ "$COMMIT_TYPE" = "test" ]; then
    DESCRIPTION="add tests"
elif [ "$COMMIT_TYPE" = "build" ]; then
    DESCRIPTION="update dependencies"
elif [ "$COMMIT_TYPE" = "ci" ]; then
    DESCRIPTION="update CI configuration"
elif [ "$COMMIT_TYPE" = "chore" ]; then
    DESCRIPTION="update project configuration"
fi

# Build commit message
COMMIT_MSG="$COMMIT_TYPE"
if [ -n "$COMMIT_SCOPE" ]; then
    COMMIT_MSG="$COMMIT_MSG($COMMIT_SCOPE)"
fi
if [ "$BREAKING_CHANGE" = true ]; then
    COMMIT_MSG="$COMMIT_MSG!"
fi
COMMIT_MSG="$COMMIT_MSG: $DESCRIPTION"

# Add breaking change footer if needed
if [ "$BREAKING_CHANGE" = true ]; then
    COMMIT_MSG="$COMMIT_MSG

BREAKING CHANGE: This change includes breaking modifications that may affect existing functionality."
fi

info "Commit message: $COMMIT_MSG"

# Step 5: Execute Commit
info "Staging all changes..."
git add -A

info "Committing changes..."
git commit -m "$COMMIT_MSG"

# Get commit hash
COMMIT_HASH=$(git rev-parse --short HEAD)

# Step 6: Push to Remote
info "Pushing to remote..."

# Detect upstream tracking branch
UPSTREAM=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || echo "")

if [ -n "$UPSTREAM" ]; then
    PUSH_DEST="$UPSTREAM"
    git push
else
    PUSH_DEST="origin/$CURRENT_BRANCH"
    git push -u origin "$CURRENT_BRANCH"
fi

# Step 7: Post-Commit Summary
echo ""
info "✓ Commit successful!"
echo "  Commit: $COMMIT_HASH"
echo "  Message: $COMMIT_MSG"
echo "  Pushed to: $PUSH_DEST"
