#!/usr/bin/bash
set -eoux pipefail

# build-appimage.sh — Build Hermes Desktop AppImage depuis le fork i18n FR
# Usage: ./build-appimage.sh [I18N_BRANCH]
# Par défaut: i18n/french-desktop

I18N_BRANCH="${1:-i18n/french-desktop}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK_DIR="/tmp/hermes-desktop-build-$$"
OUTPUT_DIR="$SCRIPT_DIR/dist"

echo "=== Hermes Desktop AppImage Build (i18n FR) ==="
echo "Fork branch:  $I18N_BRANCH"
echo "Work dir:     $WORK_DIR"

# Nettoyage
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR" "$OUTPUT_DIR"

# Cloner le fork i18n (contient déjà fr.ts + tous les patches)
echo ">>> Cloning i18n fork..."
git clone --depth=1 --branch="$I18N_BRANCH" \
  https://github.com/elgabo86/hermes-agent.git "$WORK_DIR"

# Installer dépendances (depuis la racine, --ignore-scripts pour Kinoite)
echo ">>> Installing dependencies..."
cd "$WORK_DIR"
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

# Renommer en hermes-desktop avec timestamp (pour que l'auto-update détecte les changements)
VERSION=$(echo "$(basename "$APPIMAGE")" | sed -n 's/^Hermes-\([0-9.]*\)-linux.*/\1/p')
BUILD_TS=$(date -u +%Y%m%dT%H%M%SZ)
NEWNAME="hermes-desktop-${VERSION}-${BUILD_TS}-x86_64.AppImage"
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
