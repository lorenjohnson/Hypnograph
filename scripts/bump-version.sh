#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_PATH="${PROJECT_PATH:-$REPO_ROOT/Hypnograph.xcodeproj}"
PBXPROJ_PATH="$PROJECT_PATH/project.pbxproj"
TARGET_NAME="${TARGET_NAME:-Hypnograph}"
CONFIGURATION="${CONFIGURATION:-Release}"

COMMIT=0
TAG=0
NEW_MARKETING_VERSION=""
NEW_BUILD_NUMBER=""
COMMIT_MESSAGE=""

usage() {
  cat <<'EOF'
Usage: ./scripts/bump-version.sh [options]

By default, increments CURRENT_PROJECT_VERSION by 1 for the Hypnograph release line.

Options:
  --marketing-version X.Y.Z   Set MARKETING_VERSION explicitly
  --build-number N            Set CURRENT_PROJECT_VERSION explicitly
  --commit                    Commit the version bump
  --tag                       Create a git tag for the bumped version (implies --commit)
  --message TEXT              Override the git commit message
  -h, --help                  Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --marketing-version)
      NEW_MARKETING_VERSION="${2:-}"
      shift 2
      ;;
    --build-number)
      NEW_BUILD_NUMBER="${2:-}"
      shift 2
      ;;
    --commit)
      COMMIT=1
      shift
      ;;
    --tag)
      TAG=1
      COMMIT=1
      shift
      ;;
    --message)
      COMMIT_MESSAGE="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

for required_command in xcodebuild git perl; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "error: Required command not found: $required_command" >&2
    exit 1
  fi
done

if [[ ! -f "$PBXPROJ_PATH" ]]; then
  echo "error: project file not found: $PBXPROJ_PATH" >&2
  exit 1
fi

BUILD_SETTINGS="$(xcodebuild -project "$PROJECT_PATH" -target "$TARGET_NAME" -configuration "$CONFIGURATION" -showBuildSettings 2>/dev/null)"
CURRENT_MARKETING_VERSION="$(awk -F' = ' '/MARKETING_VERSION = / { print $2; exit }' <<<"$BUILD_SETTINGS")"
CURRENT_BUILD_NUMBER="$(awk -F' = ' '/CURRENT_PROJECT_VERSION = / { print $2; exit }' <<<"$BUILD_SETTINGS")"

if [[ -z "$CURRENT_MARKETING_VERSION" || -z "$CURRENT_BUILD_NUMBER" ]]; then
  echo "error: Could not determine current version/build from Xcode build settings." >&2
  exit 1
fi

if [[ -z "$NEW_MARKETING_VERSION" ]]; then
  NEW_MARKETING_VERSION="$CURRENT_MARKETING_VERSION"
fi

if [[ -z "$NEW_BUILD_NUMBER" ]]; then
  if [[ "$NEW_MARKETING_VERSION" != "$CURRENT_MARKETING_VERSION" ]]; then
    NEW_BUILD_NUMBER="1"
  else
    NEW_BUILD_NUMBER="$((CURRENT_BUILD_NUMBER + 1))"
  fi
fi

if [[ ! "$NEW_MARKETING_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: MARKETING_VERSION must use major.minor.patch format, got: $NEW_MARKETING_VERSION" >&2
  exit 1
fi

if [[ ! "$NEW_BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "error: CURRENT_PROJECT_VERSION must be an integer, got: $NEW_BUILD_NUMBER" >&2
  exit 1
fi

if [[ "$NEW_MARKETING_VERSION" == "$CURRENT_MARKETING_VERSION" && "$NEW_BUILD_NUMBER" == "$CURRENT_BUILD_NUMBER" ]]; then
  echo "No version change needed."
  exit 0
fi

perl -0pi -e "s/MARKETING_VERSION = \Q$CURRENT_MARKETING_VERSION\E;/MARKETING_VERSION = $NEW_MARKETING_VERSION;/g; s/CURRENT_PROJECT_VERSION = \Q$CURRENT_BUILD_NUMBER\E;/CURRENT_PROJECT_VERSION = $NEW_BUILD_NUMBER;/g;" "$PBXPROJ_PATH"

TAG_NAME="v${NEW_MARKETING_VERSION}-beta.${NEW_BUILD_NUMBER}"
DEFAULT_COMMIT_MESSAGE="release: bump version to ${NEW_MARKETING_VERSION} beta ${NEW_BUILD_NUMBER}"
COMMIT_MESSAGE="${COMMIT_MESSAGE:-$DEFAULT_COMMIT_MESSAGE}"

if [[ $COMMIT -eq 1 ]]; then
  if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
    NON_VERSION_CHANGES="$(git status --porcelain --untracked-files=no | grep -v "Hypnograph.xcodeproj/project.pbxproj" || true)"
    if [[ -n "$NON_VERSION_CHANGES" ]]; then
      echo "error: Working tree has additional tracked changes. Commit or stash them before using --commit." >&2
      exit 1
    fi
  fi

  git add "$PBXPROJ_PATH"
  git commit -m "$COMMIT_MESSAGE"
fi

if [[ $TAG -eq 1 ]]; then
  if git rev-parse "$TAG_NAME" >/dev/null 2>&1; then
    echo "error: Tag already exists: $TAG_NAME" >&2
    exit 1
  fi
  git tag -a "$TAG_NAME" -m "$TAG_NAME"
fi

cat <<EOF
Updated versioning.

MARKETING_VERSION: $CURRENT_MARKETING_VERSION -> $NEW_MARKETING_VERSION
CURRENT_PROJECT_VERSION: $CURRENT_BUILD_NUMBER -> $NEW_BUILD_NUMBER
Suggested release tag: $TAG_NAME
EOF
