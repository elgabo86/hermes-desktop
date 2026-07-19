#!/usr/bin/env bash
# post-process-appimage.sh — Injecte l'auto-update dans l'AppImage Hermes Desktop
# Usage: ./post-process-appimage.sh <input.AppImage>
#
# Prérequis: appimagetool, zsyncmake (dans le PATH)
#   - appimagetool: https://github.com/AppImage/AppImageKit/releases
#   - zsyncmake: brew install zsync (ou paquet système)

set -euo pipefail

INPUT="$(realpath "$1")"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GITHUB_USER="elgabo86"
GITHUB_REPO="hermes-desktop"

if [ ! -f "$INPUT" ]; then
    echo "ERREUR: $INPUT introuvable"
    exit 1
fi

BASENAME=$(basename "$INPUT" .AppImage)
OUTPUT_DIR="$(dirname "$INPUT")"
WORK_DIR="$(mktemp -d /tmp/hermes-appimage-post-XXXXX)"
OUTPUT="$OUTPUT_DIR/$BASENAME.AppImage"
ZS_OUTPUT="$OUTPUT_DIR/$BASENAME.AppImage.zsync"

echo "=== Post-processing $BASENAME ==="
echo "Work dir: $WORK_DIR"

# ── Étape 1: Extraire l'AppImage ────────────────────────────────

echo ">>> Extraction..."
cp "$INPUT" "$WORK_DIR/original.AppImage"
chmod +x "$WORK_DIR/original.AppImage"
cd "$WORK_DIR"
./original.AppImage --appimage-extract > /dev/null
echo "Extraction OK."

# ── Étape 2: Injecter le script auto-update ─────────────────────

echo ">>> Injection du script auto-update..."
mkdir -p squashfs-root/usr/bin
cp "$SCRIPT_DIR/scripts/auto-update.sh" squashfs-root/usr/bin/auto-update
chmod +x squashfs-root/usr/bin/auto-update

# ── Étape 3: Patcher l'AppRun ───────────────────────────────────

echo ">>> Patch de l'AppRun..."
# On insère l'appel à auto-update juste avant la fin du script,
# après le bloc if [ -z "$APPIMAGE" ] (avant que le script ne quitte
# et que le trap atexit ne se déclenche).
#
# On cherche la fin du fichier et on insère avant la dernière ligne vide.

APPRUN="squashfs-root/AppRun"

# Vérifier que le script auto-update n'est pas déjà présent
if grep -q "auto-update" "$APPRUN" 2>/dev/null; then
    echo "AppRun déjà patché, on saute."
else
    # Insérer l'appel avant les dernières lignes vides
    # Stratégie: ajouter après la définition de APPIMAGE
    cat >> "$APPRUN" << 'HERMES_UPDATE_INJECT'

# ── Auto-update check (injected by post-process-appimage.sh) ──
if [ -x "$APPDIR/usr/bin/auto-update" ]; then
    "$APPDIR/usr/bin/auto-update" "$@" || true
fi
HERMES_UPDATE_INJECT
    echo "AppRun patché."
fi

# ── Étape 4: Re-packager avec updateinformation ──────────────────

echo ">>> Re-packaging avec appimagetool..."
APPMAGETOOL=$(command -v appimagetool 2>/dev/null || echo "/tmp/appimagetool/appimagetool")

# Vérifier qu'appimagetool est dispo
if ! "$APPMAGETOOL" --version &>/dev/null; then
    echo "ERREUR: appimagetool introuvable. Téléchargez-le depuis:"
    echo "  https://github.com/AppImage/AppImageKit/releases"
    exit 1
fi

# Le format pour GitHub Releases:
#   gh-releases-zsync|USER|REPO|latest|PATTERN.zsync
UPDATE_INFO="gh-releases-zsync|${GITHUB_USER}|${GITHUB_REPO}|latest|Hermes-*-x86_64.AppImage.zsync"

echo "Update information: $UPDATE_INFO"

# L'appimagetool téléchargé est lui-même une AppImage.
# Pour le CI (qui peut ne pas avoir FUSE), on utilise APPIMAGE_EXTRACT_AND_RUN.
if file "$APPMAGETOOL" | grep -q "AppImage"; then
    export APPIMAGE_EXTRACT_AND_RUN=1
fi

# Supprimer l'ancienne AppImage de sortie si elle existe
rm -f "$OUTPUT" "$ZS_OUTPUT"

"$APPMAGETOOL" \
    --updateinformation "$UPDATE_INFO" \
    --comp xz \
    squashfs-root \
    "$OUTPUT"

echo "Nouvelle AppImage: $OUTPUT"

# ── Étape 5: Vérifier que le .zsync a été généré ─────────────────

if [ -f "$ZS_OUTPUT" ]; then
    echo ">>> .zsync généré: $ZS_OUTPUT"
    ls -lh "$ZS_OUTPUT"
else
    echo ">>> Génération manuelle du .zsync..."
    zsyncmake \
        -u "https://github.com/${GITHUB_USER}/${GITHUB_REPO}/releases/latest/download/Hermes-${BASENAME#Hermes-}.AppImage" \
        -o "$ZS_OUTPUT" \
        "$OUTPUT"
    echo ".zsync généré manuellement."
fi

# ── Nettoyage ───────────────────────────────────────────────────

echo ">>> Nettoyage..."
rm -rf "$WORK_DIR"
echo "=== Terminé ==="
echo ""
echo "Fichiers produits:"
ls -lh "$OUTPUT" "$ZS_OUTPUT"
