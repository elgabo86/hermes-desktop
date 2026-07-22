#!/usr/bin/env bash
# auto-update.sh — Vérifie si une nouvelle AppImage est disponible et la télécharge
# Appelé par l'AppRun au démarrage (synchrone).
# Utilise raw.githubusercontent.com (pas d'API, pas de rate limit).
set -e

if [ -z "${APPIMAGE:-}" ] || [ "$APPIMAGE" = "$APPDIR/AppRun" ]; then
    exit 0
fi

VERSION_URL="https://raw.githubusercontent.com/elgabo86/hermes-desktop/main/VERSION"
RELEASE_URL="https://github.com/elgabo86/hermes-desktop/releases/latest/download"
CACHE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/hermes-desktop-version"

# Récupérer le timestamp de la version distante
REMOTE_VERSION=$(curl -fsS --connect-timeout 10 "$VERSION_URL" 2>/dev/null | head -1 | tr -d '[:space:]')

if [ -z "$REMOTE_VERSION" ]; then
    exit 0  # Pas de réseau
fi

# Comparer avec le cache local
if [ -f "$CACHE_FILE" ] && [ "$(cat "$CACHE_FILE")" = "$REMOTE_VERSION" ]; then
    exit 0  # Déjà à jour
fi

# Trouver le nom exact du fichier via la page de release (sans API)
DL_PAGE=$(curl -fsS --connect-timeout 10 "https://github.com/elgabo86/hermes-desktop/releases/latest" 2>/dev/null)
APPIMAGE_NAME=$(echo "$DL_PAGE" | grep -o 'hermes-desktop-[0-9.]*-[0-9]*T[0-9]*Z-x86_64\.AppImage' | head -1)

if [ -z "$APPIMAGE_NAME" ]; then
    exit 0
fi

echo "[auto-update] Nouvelle version disponible ($REMOTE_VERSION), téléchargement..."
TEMP=$(mktemp "/tmp/hermes-desktop-XXXXXX.AppImage")

if curl -fSL --connect-timeout 30 --max-time 600 -o "$TEMP" "${RELEASE_URL}/${APPIMAGE_NAME}" 2>/dev/null; then
    chmod +x "$TEMP"
    mv "$TEMP" "$APPIMAGE"
    mkdir -p "$(dirname "$CACHE_FILE")"
    echo "$REMOTE_VERSION" > "$CACHE_FILE"
    echo "[auto-update] Mise à jour terminée. Redémarrez Hermes Desktop."
else
    rm -f "$TEMP"
    echo "[auto-update] Échec du téléchargement."
fi
