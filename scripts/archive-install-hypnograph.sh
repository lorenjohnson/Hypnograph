#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${FULL_PRODUCT_NAME:-Hypnograph.app}"
APPS_DIR="/Applications"

candidates=()

if [[ -n "${TARGET_BUILD_DIR:-}" ]]; then
  candidates+=("$TARGET_BUILD_DIR/$APP_NAME")
fi
if [[ -n "${BUILT_PRODUCTS_DIR:-}" ]]; then
  candidates+=("$BUILT_PRODUCTS_DIR/$APP_NAME")
fi
if [[ -n "${ARCHIVE_PRODUCTS_PATH:-}" ]]; then
  candidates+=("$ARCHIVE_PRODUCTS_PATH/Applications/$APP_NAME")
  candidates+=("$ARCHIVE_PRODUCTS_PATH/$APP_NAME")
fi
if [[ -n "${ARCHIVE_PATH:-}" ]]; then
  candidates+=("$ARCHIVE_PATH/Products/Applications/$APP_NAME")
fi

SRC_APP=""
for candidate in "${candidates[@]}"; do
  if [[ -d "$candidate" ]]; then
    SRC_APP="$candidate"
    break
  fi
done

if [[ -z "$SRC_APP" ]]; then
  echo "error: Could not locate $APP_NAME from archive build products." >&2
  echo "Checked paths:" >&2
  for candidate in "${candidates[@]}"; do
    echo "  - $candidate" >&2
  done
  exit 1
fi

DEST_APP="$APPS_DIR/$APP_NAME"

if [[ ! -w "$APPS_DIR" ]]; then
  echo "error: $APPS_DIR is not writable by current user. Could not install $APP_NAME." >&2
  exit 1
fi

echo "Installing $APP_NAME to $APPS_DIR"
if [[ -d "$DEST_APP" ]]; then
  rm -rf "$DEST_APP"
fi

if command -v ditto >/dev/null 2>&1; then
  ditto "$SRC_APP" "$DEST_APP"
else
  cp -R "$SRC_APP" "$DEST_APP"
fi

echo "Installed: $DEST_APP"
