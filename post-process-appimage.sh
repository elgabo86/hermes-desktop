#!/usr/bin/env bash
# post-process-appimage.sh — Prépare l'AppImage pour l'auto-update
# Usage: ./post-process-appimage.sh <input.AppImage>
#
# Injecte le script auto-update dans l'AppImage et patche l'AppRun
# pour le lancer en background au démarrage.

set -euo pipefail

INPUT="$(realpath "$1")"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ ! -f "$INPUT" ]; then
    echo "ERREUR: $INPUT introuvable"
    exit 1
fi

BASENAME=$(basename "$INPUT" .AppImage)
OUTPUT_DIR="$(dirname "$INPUT")"
WORK_DIR="$(mktemp -d /tmp/hermes-appimage-post-XXXXX)"
OUTPUT="$OUTPUT_DIR/$BASENAME.AppImage"

echo "=== Post-processing $BASENAME ==="
echo "Work dir: $WORK_DIR"

# ── Étape 1: Extraire le runtime et le SquashFS ─────────────────
echo ">>> Extraction..."

# Trouver l'offset du SquashFS (dernière occurrence de 'hsqs')
OFFSET=$(strings -t d "$INPUT" | grep "hsqs" | awk '{print $1}' | sort -n | tail -1)
if [ -z "$OFFSET" ] || [ "$OFFSET" -lt 100000 ]; then
    echo "ERREUR: impossible de trouver l'offset SquashFS"
    exit 1
fi
echo "  Offset SquashFS: $OFFSET"

dd if="$INPUT" of="$WORK_DIR/runtime" bs=1 count="$OFFSET" 2>/dev/null
chmod +x "$WORK_DIR/runtime"

cp "$INPUT" "$WORK_DIR/original.AppImage"
chmod +x "$WORK_DIR/original.AppImage"
cd "$WORK_DIR"
./original.AppImage --appimage-extract > /dev/null
echo "  Extraction OK."

# ── Étape 2: Injecter le script auto-update ─────────────────────
echo ">>> Injection du script auto-update..."
mkdir -p squashfs-root/usr/bin
cp "$SCRIPT_DIR/scripts/auto-update.sh" squashfs-root/usr/bin/auto-update
chmod +x squashfs-root/usr/bin/auto-update
echo "  Script embarqué."

# ── Étape 3: Patcher l'AppRun ───────────────────────────────────
echo ">>> Patch de l'AppRun..."
APPRUN="squashfs-root/AppRun"

# Injecter le PATH brew si nécessaire
if ! grep -q 'linuxbrew.*PATH' "$APPRUN" 2>/dev/null; then
    awk -i inplace '
/^export PATH="\$\{APPDIR\}:\$\{APPDIR\}\/usr\/sbin/ {
    print
    print ""
    print "# ── Homebrew PATH (injected) ──"
    print "if [ -d \"/home/linuxbrew/.linuxbrew/bin\" ]; then"
    print "    export PATH=\"/home/linuxbrew/.linuxbrew/bin:$PATH\""
    print "fi"
    next
}
{ print }' "$APPRUN"
    echo "  Brew PATH injecté."
fi

# Injecter l'appel auto-update en background
if grep -q 'auto-update.*&' "$APPRUN" 2>/dev/null; then
    echo "  AppRun déjà patché (auto-update), on saute."
else
    sed -i '/^# ── Auto-update check/d' "$APPRUN"
    sed -i '/^if.*auto-update.*then$/,/^fi$/d' "$APPRUN" 2>/dev/null || true
    sed -i '/^if.*auto-update.*then$/,/^fi$/d' "$APPRUN" 2>/dev/null || true
    cat >> "$APPRUN" << 'HERMES_UPDATE_INJECT'

# ── Auto-update check (injected) ──
if [ -x "$APPDIR/usr/bin/auto-update" ]; then
    "$APPDIR/usr/bin/auto-update" "$@"
fi
HERMES_UPDATE_INJECT
    echo "  AppRun patché (auto-update)."
fi

# ── Étape 4: Reconstruire le SquashFS ───────────────────────────
echo ">>> Reconstruction du SquashFS..."
mksquashfs squashfs-root "$WORK_DIR/new.squashfs" \
    -comp xz \
    -noappend \
    -no-progress 2>&1 | tail -3

# ── Étape 5: Assembler ──────────────────────────────────────────
echo ">>> Assemblage..."
cat "$WORK_DIR/runtime" "$WORK_DIR/new.squashfs" > "$OUTPUT"
chmod +x "$OUTPUT"

# ── Étape 6: Vérification ───────────────────────────────────────
echo ">>> Vérification..."
if [ -x "$OUTPUT" ]; then
    echo "✅ OK — $OUTPUT"
else
    echo "❌ ERREUR"
    exit 1
fi

# ── Nettoyage ───────────────────────────────────────────────────
rm -rf "$WORK_DIR"
echo "=== Terminé ==="
