#!/usr/bin/env bash
# auto-update.sh — Vérifie si une nouvelle AppImage est disponible et la télécharge
# Appelé par l'AppRun au démarrage (synchrone).
# Lit la version locale depuis build-version embarqué (indépendant du nom de fichier).
# Utilise zsync embarqué pour le delta, fallback curl pour le téléchargement complet.
set -e

if [ -z "${APPIMAGE:-}" ] || [ "$APPIMAGE" = "$APPDIR/AppRun" ]; then
    exit 0
fi

VERSION_URL="https://github.com/elgabo86/hermes-desktop/releases/latest/download/VERSION"
RELEASE_URL="https://github.com/elgabo86/hermes-desktop/releases/latest/download"

# ── Version locale (priorité: fichier embarqué > nom du fichier) ──
LOCAL_VERSION=""
if [ -f "$APPDIR/usr/share/hermes/build-version" ]; then
    LOCAL_VERSION=$(cat "$APPDIR/usr/share/hermes/build-version" | tr -d '[:space:]')
fi

if [ -z "$LOCAL_VERSION" ]; then
    LOCAL_VERSION=$(echo "$APPIMAGE" | grep -oP '[0-9]{8}T[0-9]{6}Z(?=-x86_64\.AppImage)' | head -1 || true)
fi

if [ -z "$LOCAL_VERSION" ]; then
    exit 0  # Pas de version identifiable
fi

# ── Version distante ──
REMOTE_VERSION=$(curl -fsSL --connect-timeout 10 "$VERSION_URL" 2>/dev/null | head -1 | tr -d '[:space:]')

if [ -z "$REMOTE_VERSION" ]; then
    exit 0  # Pas de réseau
fi

# ── Déjà à jour ? ──
if [ "$LOCAL_VERSION" = "$REMOTE_VERSION" ]; then
    exit 0
fi

# ── Nom du fichier distant ──
APPIMAGE_NAME=$(curl -fsSL --connect-timeout 10 "${RELEASE_URL}/LATEST" 2>/dev/null | head -1 | tr -d '[:space:]')

if [ -z "$APPIMAGE_NAME" ]; then
    exit 0
fi

echo "[auto-update] Nouvelle version disponible ($REMOTE_VERSION)..."

TEMP=$(mktemp "/tmp/hermes-desktop-XXXXXX.AppImage")
UPDATED=0

# ── Essayer zsync (delta) si zsync embarqué est disponible ──
ZSYNC="$APPDIR/usr/bin/zsync"
if [ -x "$ZSYNC" ]; then
    ZSYNC_URL="${RELEASE_URL}/${APPIMAGE_NAME}.zsync"
    echo "[auto-update] Téléchargement delta via zsync..."
    if "$ZSYNC" -i "$APPIMAGE" -o "$TEMP" "$ZSYNC_URL" 2>/dev/null; then
        chmod +x "$TEMP"
        mv "$TEMP" "$APPIMAGE"
        echo "[auto-update] Mise à jour delta terminée. Redémarrez Hermes Desktop."
        UPDATED=1
    else
        echo "[auto-update] Échec du delta, fallback téléchargement complet..."
    fi
fi

# ── Fallback: téléchargement complet via curl ──
if [ "$UPDATED" = "0" ]; then
    echo "[auto-update] Téléchargement complet..."
    if curl -fSL --connect-timeout 30 --max-time 600 -o "$TEMP" "${RELEASE_URL}/${APPIMAGE_NAME}" 2>/dev/null; then
        chmod +x "$TEMP"
        mv "$TEMP" "$APPIMAGE"
        echo "[auto-update] Mise à jour terminée. Redémarrez Hermes Desktop."
    else
        rm -f "$TEMP"
        echo "[auto-update] Échec du téléchargement."
    fi
fi
