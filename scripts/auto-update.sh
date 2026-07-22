#!/usr/bin/env bash
# auto-update.sh — Vérifie si une nouvelle AppImage est disponible et la télécharge
# Appelé en background par l'AppRun au démarrage.
set -e

# Pas une AppImage → rien à faire
if [ -z "${APPIMAGE:-}" ] || [ "$APPIMAGE" = "$APPDIR/AppRun" ]; then
    exit 0
fi

REPO="elgabo86/hermes-desktop"
RELEASE_URL="https://github.com/${REPO}/releases/download/latest"

# Récupérer la date de la dernière release via l'API GitHub (rapide, pas de téléchargement)
REMOTE_DATE=$(curl -fsS --connect-timeout 10 -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null | \
  grep -o '"published_at": "[^"]*"' | cut -d'"' -f4)

if [ -z "$REMOTE_DATE" ]; then
    exit 0  # Pas de réseau, on abandonne silencieusement
fi

REMOTE_TS=$(date -d "$REMOTE_DATE" +%s 2>/dev/null || date -jf "%Y-%m-%dT%H:%M:%SZ" "$REMOTE_DATE" +%s 2>/dev/null)
LOCAL_TS=$(stat -c %Y "$APPIMAGE" 2>/dev/null)

if [ -z "$REMOTE_TS" ] || [ -z "$LOCAL_TS" ]; then
    exit 0
fi

# Si le fichier local est déjà plus récent ou identique, rien à faire
if [ "$LOCAL_TS" -ge "$REMOTE_TS" ]; then
    exit 0
fi

# Télécharger la nouvelle AppImage
echo "[auto-update] Nouvelle version disponible, téléchargement..."
TEMP=$(mktemp "/tmp/hermes-desktop-XXXXXX.AppImage")

# Lister les assets pour trouver le nom exact du fichier
DL_URL=$(curl -fsS "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null | \
  grep -o '"browser_download_url": "[^"]*x86_64\.AppImage"' | head -1 | cut -d'"' -f4)

if [ -z "$DL_URL" ]; then
    rm -f "$TEMP"
    exit 0
fi

if curl -fSL --connect-timeout 30 --max-time 600 -o "$TEMP" "$DL_URL" 2>/dev/null; then
    chmod +x "$TEMP"
    mv "$TEMP" "$APPIMAGE"
    echo "[auto-update] Mise à jour terminée. Redémarrez Hermes Desktop."
else
    rm -f "$TEMP"
    echo "[auto-update] Échec du téléchargement."
fi
