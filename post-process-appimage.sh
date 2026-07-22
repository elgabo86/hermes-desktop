#!/usr/bin/env bash
# post-process-appimage.sh — Injecte l'auto-update dans l'AppImage Hermes Desktop
# Usage: ./post-process-appimage.sh <input.AppImage>
#
# N'utilise PAS appimagetool (AppImageKit est archivé).
# Reconstruit manuellement avec mksquashfs + injection d'updateinformation.

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

# Vérifier les outils requis
for tool in mksquashfs zsyncmake; do
    if ! command -v "$tool" &>/dev/null; then
        echo "ERREUR: $tool introuvable. Installez-le (apt install squashfs-tools zsync)."
        exit 1
    fi
done

# ── Étape 1: Extraire le runtime et le SquashFS ─────────────────

echo ">>> Extraction du runtime..."

# Trouver l'offset du SquashFS. Le magic 'hsqs' peut apparaître plusieurs fois.
# On prend la DERNIÈRE occurrence (la plus loin dans le fichier) qui est le vrai
# début du système de fichiers SquashFS.
OFFSET=$(strings -t d "$INPUT" | grep "hsqs" | awk '{print $1}' | sort -n | tail -1)
if [ -z "$OFFSET" ] || [ "$OFFSET" -lt 100000 ]; then
    echo "ERREUR: impossible de trouver l'offset SquashFS dans $INPUT"
    echo "  Occurences trouvées:"
    strings -t d "$INPUT" | grep "hsqs"
    exit 1
fi
echo "  Offset SquashFS: $OFFSET"

# Extraire le runtime (tout avant le SquashFS)
echo ">>> Extraction du runtime ($OFFSET bytes)..."
dd if="$INPUT" of="$WORK_DIR/runtime" bs=1 count="$OFFSET" 2>/dev/null
chmod +x "$WORK_DIR/runtime"

# Extraire le contenu de l'AppImage
echo ">>> Extraction du contenu..."
cp "$INPUT" "$WORK_DIR/original.AppImage"
chmod +x "$WORK_DIR/original.AppImage"
cd "$WORK_DIR"
./original.AppImage --appimage-extract > /dev/null
echo "Extraction OK."

# ── Étape 2: Télécharger et injecter l'outil de mise à jour ─────

echo ">>> Téléchargement de appimageupdatetool..."
UPDATE_TOOL_URL="https://github.com/AppImage/AppImageUpdate/releases/download/continuous/appimageupdatetool-x86_64.AppImage"
mkdir -p squashfs-root/usr/bin

if command -v curl &>/dev/null; then
    curl -sSL --connect-timeout 30 "$UPDATE_TOOL_URL" -o squashfs-root/usr/bin/appimageupdatetool
elif command -v wget &>/dev/null; then
    wget -q --timeout=30 "$UPDATE_TOOL_URL" -O squashfs-root/usr/bin/appimageupdatetool
else
    echo "ERREUR: ni curl ni wget disponible."
    exit 1
fi
chmod +x squashfs-root/usr/bin/appimageupdatetool
echo "  Outil embarqué."

echo ">>> Injection du script auto-update..."
cp "$SCRIPT_DIR/scripts/auto-update.sh" squashfs-root/usr/bin/auto-update
chmod +x squashfs-root/usr/bin/auto-update

# ── Étape 3: Patcher l'AppRun ───────────────────────────────────

echo ">>> Patch de l'AppRun..."
APPRUN="squashfs-root/AppRun"

# ── Injecter le PATH brew si nécessaire (pour le rebuild desktop) ──
# Sans ça, 'hermes desktop --build-only' ne trouve pas npm sur les systèmes
# où Node.js est installé via Homebrew (ex: Fedora Kinoite).
if ! grep -q 'linuxbrew.*PATH' "$APPRUN" 2>/dev/null; then
    # Insère après la ligne 'export PATH="${APPDIR}:${APPDIR}/usr/sbin...'
    sed -i '/^export PATH="\${APPDIR}:\${APPDIR}\/usr\/sbin/a\
\
# ── Homebrew PATH (injected) ──\
# Ajoute linuxbrew au PATH si présent (npm requis pour le rebuild desktop)\
if [ -d "/home/linuxbrew/.linuxbrew/bin" ]; then\
    export PATH="/home/linuxbrew/.linuxbrew/bin:$PATH"\
fi' "$APPRUN"
    echo "  Brew PATH injecté dans l'AppRun."
else
    echo "  Brew PATH déjà injecté, on saute."
fi

if grep -q 'auto-update.*&' "$APPRUN" 2>/dev/null; then
    echo "  AppRun déjà patché (background), on saute."
else
    # Nettoyer un éventuel ancien patch (sans background)
    sed -i '/^# ── Auto-update check/d' "$APPRUN"
    sed -i '/^if.*auto-update.*then$/,/^fi$/d' "$APPRUN" 2>/dev/null || true
    sed -i '/^if.*auto-update.*then$/,/^fi$/d' "$APPRUN" 2>/dev/null || true
    # Injecter le nouveau patch
    cat >> "$APPRUN" << 'HERMES_UPDATE_INJECT'

# ── Auto-update check (injected) ──
if [ -x "$APPDIR/usr/bin/auto-update" ]; then
    "$APPDIR/usr/bin/auto-update" "$@" &
fi
HERMES_UPDATE_INJECT
    echo "  AppRun patché (background)."
fi

# ── Étape 4: Reconstruire le SquashFS ───────────────────────────

echo ">>> Reconstruction du SquashFS..."
mksquashfs squashfs-root "$WORK_DIR/new.squashfs" \
    -comp xz \
    -noappend \
    -no-progress 2>&1 | tail -3

# ── Étape 5: Assembler l'AppImage ───────────────────────────────

echo ">>> Assemblage de l'AppImage..."
cat "$WORK_DIR/runtime" "$WORK_DIR/new.squashfs" > "$OUTPUT"
chmod +x "$OUTPUT"

# ── Étape 6: Injecter l'updateinformation ───────────────────────

echo ">>> Injection de l'updateinformation..."
# Format: gh-releases-zsync|USER|REPO|latest|PATTERN.zsync
UPDATE_INFO="gh-releases-zsync|${GITHUB_USER}|${GITHUB_REPO}|latest|hermes-desktop-*-x86_64.AppImage.zsync"

# AppImage update information format: magic 'AI\x02' + string
printf 'AI\x02%s' "$UPDATE_INFO" >> "$OUTPUT"
echo "  Update info: $UPDATE_INFO"

# ── Étape 7: Générer le .zsync ───────────────────────────────────

echo ">>> Génération du .zsync..."
# Le tag de release est toujours 'latest' (écrasé à chaque build)
DL_URL="https://github.com/${GITHUB_USER}/${GITHUB_REPO}/releases/download/latest/${BASENAME}.AppImage"

zsyncmake \
    -u "$DL_URL" \
    -o "$ZS_OUTPUT" \
    "$OUTPUT" 2>&1

echo "  .zsync: $ZS_OUTPUT"

# ── Étape 8: Vérification ───────────────────────────────────────

echo ">>> Vérification..."
if [ -x "$OUTPUT" ] && [ -f "$ZS_OUTPUT" ]; then
    echo "✅ OK"
else
    echo "❌ ERREUR: fichiers manquants"
    exit 1
fi

# Vérifier que l'updateinformation est lisible
if strings "$OUTPUT" | grep -q "gh-releases-zsync"; then
    echo "  Update info présente dans l'AppImage."
fi

# ── Nettoyage ───────────────────────────────────────────────────

echo ">>> Nettoyage..."
rm -rf "$WORK_DIR"

echo "=== Terminé ==="
echo "Fichiers produits:"
ls -lh "$OUTPUT" "$ZS_OUTPUT"
