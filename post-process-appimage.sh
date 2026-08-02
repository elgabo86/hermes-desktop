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

# ── Étape 2: Injecter le script auto-update, zsync et build-version ─────
echo ">>> Injection des scripts..."
mkdir -p squashfs-root/usr/bin squashfs-root/usr/share/hermes

cp "$SCRIPT_DIR/scripts/auto-update.sh" squashfs-root/usr/bin/auto-update
chmod +x squashfs-root/usr/bin/auto-update
echo "  auto-update embarqué."

# Splash Electron (fenêtre de progression pendant l'auto-update)
# On crée un dossier splash/ avec un hardlink du binaire Electron + un mini app.asar.
# Electron résout resources/app.asar relativement à /proc/self/exe → notre asar splash.
SPLASH_BUILD="$WORK_DIR/splash-app"
rm -rf "$SPLASH_BUILD"
mkdir -p "$SPLASH_BUILD"
cp "$SCRIPT_DIR/splash/package.json" "$SPLASH_BUILD/"
cp "$SCRIPT_DIR/splash/splash.js" "$SPLASH_BUILD/"
cp "$SCRIPT_DIR/splash/splash.html" "$SPLASH_BUILD/"

# Construire l'asar splash avec @electron/asar (déjà dans node_modules du build)
if command -v npx >/dev/null 2>&1; then
    npx --yes @electron/asar pack "$SPLASH_BUILD" "$WORK_DIR/splash.asar" 2>/dev/null || {
        echo "  ATTENTION: asar splash non construit (npx/asar manquant)."
    }
else
    echo "  ATTENTION: npx absent, pas d'asar splash."
fi

if [ -f "$WORK_DIR/splash.asar" ]; then
    SPLASH_DIR="squashfs-root/usr/share/hermes/splash"
    mkdir -p "$SPLASH_DIR/resources"
    # Hardlink du binaire Electron (même inode, zéro duplication)
    ln squashfs-root/Hermes "$SPLASH_DIR/splash"
    # Mini asar splash
    cp "$WORK_DIR/splash.asar" "$SPLASH_DIR/resources/app.asar"
    # Symlinks vers les libs Electron du parent (le binaire les cherche à côté de lui)
    for f in chrome_100_percent.pak chrome_200_percent.pak chrome-sandbox chrome_crashpad_handler icudtl.dat libEGL.so libffmpeg.so libGLESv2.so libvk_swiftshader.so libvulkan.so.1 resources.pak snapshot_blob.bin v8_context_snapshot.bin vk_swiftshader_icd.json locales; do
        [ -e "squashfs-root/$f" ] && ln -sf "../../../../$f" "$SPLASH_DIR/$f"
    done
    echo "  splash Electron embarqué (hardlink binaire + mini asar)."
else
    echo "  Splash non embarquée (asar manquant)."
fi

if [ -x "$SCRIPT_DIR/scripts/zsync" ]; then
    cp "$SCRIPT_DIR/scripts/zsync" squashfs-root/usr/bin/zsync
    chmod +x squashfs-root/usr/bin/zsync
    echo "  zsync embarqué."
else
    echo "  ATTENTION: scripts/zsync absent, pas de delta update."
fi

BUILD_VERSION_FILE="$SCRIPT_DIR/dist/build-version"
if [ -f "$BUILD_VERSION_FILE" ]; then
    cp "$BUILD_VERSION_FILE" squashfs-root/usr/share/hermes/build-version
    echo "  build-version embarqué."
else
    echo "  ATTENTION: dist/build-version absent."
fi

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
    # Si l'auto-update a remplacé le fichier sur disque, relancer la nouvelle AppImage
    # au lieu de continuer avec l'ancienne (encore montée en mémoire).
    for marker in /tmp/hermes-desktop-updated-*; do
        if [ -f "$marker" ]; then
            rm -f "$marker"
            if [ -n "${APPIMAGE:-}" ] && [ -x "$APPIMAGE" ]; then
                echo "[auto-update] Relance de la nouvelle AppImage..."
                exec "$APPIMAGE" "$@"
            fi
        fi
    done
fi
HERMES_UPDATE_INJECT
    echo "  AppRun patché (auto-update + relance)."
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
