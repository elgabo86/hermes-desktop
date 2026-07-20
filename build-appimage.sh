#!/usr/bin/bash
set -eoux pipefail

# build-appimage.sh — Build Hermes Desktop AppImage avec patches français
# Usage: ./build-appimage.sh [UPSTREAM_TAG|UPSTREAM_COMMIT]
# Par défaut: upstream/main

UPSTREAM_REF="${1:-main}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK_DIR="/tmp/hermes-desktop-build-$$"
OUTPUT_DIR="$SCRIPT_DIR/dist"

echo "=== Hermes Desktop AppImage Build ==="
echo "Upstream ref: $UPSTREAM_REF"
echo "Work dir:     $WORK_DIR"

# Nettoyage
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR" "$OUTPUT_DIR"

# Clone upstream
echo ">>> Cloning upstream..."
git clone --depth=1 --branch="$UPSTREAM_REF" \
  https://github.com/NousResearch/hermes-agent.git "$WORK_DIR"

# Appliquer les patches
echo ">>> Applying patches..."
cd "$WORK_DIR"
if [ -f "$SCRIPT_DIR/patches/upstream-files.patch" ]; then
  git apply "$SCRIPT_DIR/patches/upstream-files.patch" || {
    echo "WARNING: upstream-files.patch failed, trying --reject..."
    git apply --reject "$SCRIPT_DIR/patches/upstream-files.patch" || true
  }
fi
if [ -f "$SCRIPT_DIR/patches/french-files.patch" ]; then
  git apply "$SCRIPT_DIR/patches/french-files.patch" || {
    echo "ERROR: french-files.patch failed to apply. Upstream may have diverged."
    echo "Update the patch (french-files.patch) and retry."
    exit 1
  }
fi

# Installer dépendances (depuis la racine, --ignore-scripts pour Kinoite)
echo ">>> Installing dependencies..."
npm install --ignore-scripts

# Builder l'AppImage
echo ">>> Building AppImage..."
cd apps/desktop
npm run build
npm run builder -- --linux AppImage

# Copier le résultat
APPIMAGE="$(ls release/Hermes-*.AppImage 2>/dev/null | head -1)"
if [ -z "$APPIMAGE" ]; then
  echo "ERROR: AppImage not found in release/"
  exit 1
fi

cp "$APPIMAGE" "$OUTPUT_DIR/"
echo "=== Build done: $OUTPUT_DIR/$(basename "$APPIMAGE") ==="

# Renommer en hermes-desktop
VERSION=$(echo "$(basename "$APPIMAGE")" | sed -n 's/^Hermes-\([0-9.]*\)-linux.*/\1/p')
NEWNAME="hermes-desktop-${VERSION}-x86_64.AppImage"
mv "$OUTPUT_DIR/$(basename "$APPIMAGE")" "$OUTPUT_DIR/$NEWNAME"
echo ">>> Renommé: $OUTPUT_DIR/$NEWNAME"
APPIMAGE_NAME="$NEWNAME"

# ── Post-processing: injecter l'auto-update ─────────────────────

POST_PROCESS="$SCRIPT_DIR/post-process-appimage.sh"
if [ -x "$POST_PROCESS" ]; then
    echo ">>> Post-processing (auto-updater)..."
    ORIGINAL="$OUTPUT_DIR/$APPIMAGE_NAME"
    "$POST_PROCESS" "$ORIGINAL"
    echo ">>> Post-processing terminé."
else
    echo "WARNING: post-process-appimage.sh non trouvé, pas d'auto-updater."
fi

# Nettoyage
rm -rf "$WORK_DIR"
