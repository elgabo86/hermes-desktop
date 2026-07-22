#!/usr/bin/env bash
# auto-update.sh — Vérifie si une nouvelle AppImage est disponible et la télécharge
# Appelé en background par l'AppRun au démarrage.
set -e

# Pas une AppImage → rien à faire
if [ -z "${APPIMAGE:-}" ] || [ "$APPIMAGE" = "$APPDIR/AppRun" ]; then
    exit 0
fi

REPO="elgabo86/hermes-desktop"
CACHE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/hermes-desktop-update"

# Récupérer la date de la dernière release via l'API GitHub
REMOTE_DATE=$(curl -fsS --connect-timeout 10 -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null | \
  grep -o '"published_at": "[^"]*"' | cut -d'"' -f4)

if [ -z "$REMOTE_DATE" ]; then
    exit 0  # Pas de réseau
fi

# Comparer avec la date stockée dans le cache
if [ -f "$CACHE_FILE" ]; then
    CACHED_DATE=$(cat "$CACHE_FILE")
    if [ "$REMOTE_DATE" = "$CACHED_DATE" ]; then
        exit 0  # Déjà à jour
    fi
fi

# Nouvelle version disponible : télécharger
echo "[auto-update] Nouvelle version disponible, téléchargement..."
TEMP=$(mktemp "/tmp/hermes-desktop-XXXXXX.AppImage")

DL_URL=$(curl -fsS "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null | \
  grep -o '"browser_download_url": "[^"]*x86_64\.AppImage"' | head -1 | cut -d'"' -f4)

if [ -z "$DL_URL" ]; then
    rm -f "$TEMP"
    exit 0
fi

if curl -fSL --connect-timeout 30 --max-time 600 -o "$TEMP" "$DL_URL" 2>/dev/null; then
    chmod +x "$TEMP"
    mv "$TEMP" "$APPIMAGE"
    mkdir -p "$(dirname "$CACHE_FILE")"
    echo "$REMOTE_DATE" > "$CACHE_FILE"
    echo "[auto-update] Mise à jour terminée. Redémarrez Hermes Desktop."
else
    rm -f "$TEMP"
    echo "[auto-update] Échec du téléchargement."
fi
