#!/usr/bin/env bash
# auto-update.sh — Vérifie si une nouvelle AppImage est disponible et la télécharge
# Appelé par l'AppRun au démarrage (synchrone).
# Compare le timestamp embarqué dans le nom de l'AppImage avec la version distante.
# Pas de cache externe : la source de vérité est le nom du fichier.
set -e

if [ -z "${APPIMAGE:-}" ] || [ "$APPIMAGE" = "$APPDIR/AppRun" ]; then
    exit 0
fi

VERSION_URL="https://github.com/elgabo86/hermes-desktop/releases/latest/download/VERSION"
RELEASE_URL="https://github.com/elgabo86/hermes-desktop/releases/latest/download"

# Extraire le timestamp local depuis le nom du fichier
# Format: hermes-desktop-{semver}-{TIMESTAMP}-x86_64.AppImage
LOCAL_VERSION=$(echo "$APPIMAGE" | grep -oP '[0-9]{8}T[0-9]{6}Z(?=-x86_64\.AppImage)' | head -1 || true)

if [ -z "$LOCAL_VERSION" ]; then
    exit 0  # Nom de fichier non standard, on ignore
fi

# Récupérer la version distante
REMOTE_VERSION=$(curl -fsSL --connect-timeout 10 "$VERSION_URL" 2>/dev/null | head -1 | tr -d '[:space:]')

if [ -z "$REMOTE_VERSION" ]; then
    exit 0  # Pas de réseau
fi

# Déjà à jour ?
if [ "$LOCAL_VERSION" = "$REMOTE_VERSION" ]; then
    exit 0
fi

# Trouver le nom exact du fichier via LATEST (asset de la release)
APPIMAGE_NAME=$(curl -fsSL --connect-timeout 10 "${RELEASE_URL}/LATEST" 2>/dev/null | head -1 | tr -d '[:space:]')

if [ -z "$APPIMAGE_NAME" ]; then
    exit 0
fi

echo "[auto-update] Nouvelle version disponible ($REMOTE_VERSION), téléchargement..."
TEMP=$(mktemp "/tmp/hermes-desktop-XXXXXX.AppImage")

if curl -fSL --connect-timeout 30 --max-time 600 -o "$TEMP" "${RELEASE_URL}/${APPIMAGE_NAME}" 2>/dev/null; then
    chmod +x "$TEMP"
    mv "$TEMP" "$APPIMAGE"
    echo "[auto-update] Mise à jour terminée. Redémarrez Hermes Desktop."
else
    rm -f "$TEMP"
    echo "[auto-update] Échec du téléchargement."
fi
