#!/usr/bin/env bash
# auto-update.sh — Vérifie si une nouvelle AppImage est disponible et la télécharge
# Appelé par l'AppRun au démarrage (synchrone).
# Lit la version locale depuis build-version embarqué (indépendant du nom de fichier).
# Utilise zsync embarqué pour le delta, fallback curl pour le téléchargement complet.
# Affiche une fenêtre splash Electron pendant l'opération.
# Après mise à jour, crée un marker pour que l'AppRun relance la nouvelle AppImage.
set -e

if [ -z "${APPIMAGE:-}" ] || [ "$APPIMAGE" = "$APPDIR/AppRun" ]; then
    exit 0
fi

VERSION_URL="https://github.com/elgabo86/hermes-desktop/releases/latest/download/VERSION"
RELEASE_URL="https://github.com/elgabo86/hermes-desktop/releases/latest/download"
CACHE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/hermes-desktop-version"

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

# ── Démarrer la fenêtre splash Electron (si disponible) ──────────────
SPLASH_PID=""
SPLASH_FIFO="/tmp/hermes-splash-$$"

_send_splash() {
    [ -z "$SPLASH_PID" ] && return 0
    [ ! -p "$SPLASH_FIFO" ] && return 0
    echo "$1" > "$SPLASH_FIFO" 2>/dev/null || true
}

_start_splash() {
    local splash_bin="$APPDIR/usr/share/hermes/splash/splash"

    # Le binaire splash (hardlink Electron avec son propre resources/app.asar) doit exister
    if [ ! -x "$splash_bin" ]; then
        echo "[auto-update] splash:$splash_bin inexécutable, pas de splash" >&2
        return 1
    fi

    # Sous Wayland (Fedora Kinoite), Electron nécessite parfois Ozone
    # pour afficher une fenêtre sans serveur X.
    local ozone_flags=""
    if [ -n "${WAYLAND_DISPLAY:-}" ]; then
        ozone_flags="--enable-features=UseOzonePlatform --ozone-platform=wayland"
    fi

    # Créer le FIFO avant de lancer la splash
    rm -f "$SPLASH_FIFO"
    mkfifo "$SPLASH_FIFO" 2>/dev/null || {
        echo "[auto-update] Impossible de créer le FIFO $SPLASH_FIFO" >&2
        return 1
    }

    # Lancer la splash en arrière-plan (non bloquant)
    # Le binaire Electron (hardlink) charge son propre resources/app.asar splash.
    # --no-sandbox car on est dans un AppImage sans user namespaces garantis
    "$splash_bin" --no-sandbox $ozone_flags "$SPLASH_FIFO" >/dev/null 2>&1 &
    SPLASH_PID=$!

    # Ouvrir le FIFO en lecture-écriture (non bloquant) pour garder la splash en vie
    exec 3<>/dev/null 2>/dev/null || true

    # Attendre que la splash soit prête à recevoir des messages (max 3s)
    local waited=0
    while [ ! -p "$SPLASH_FIFO" ] && [ $waited -lt 30 ]; do
        sleep 0.1
        waited=$((waited + 1))
    done

    return 0
}

_close_splash() {
    if [ -n "$SPLASH_PID" ]; then
        # Attendre que la splash ait traité tous les messages (important pour FileZilla-like)
        sleep 0.5

        # Fermer le fd du FIFO → la splash détecte la fin et se ferme
        exec 3>&- 2>/dev/null || true
        sleep 0.2

        # SIGTERM d'abord, puis SIGKILL si nécessaire
        kill -TERM "$SPLASH_PID" 2>/dev/null || true
        sleep 0.3
        kill -KILL "$SPLASH_PID" 2>/dev/null || true
        rm -f "$SPLASH_FIFO"
        SPLASH_PID=""
    fi
}

# Trap pour toujours fermer la splash en sortie
trap _close_splash EXIT

# ── Lancement de la splash ──
_start_splash || echo "[auto-update] Splash non démarrée" >&2
_send_splash '{"status":"Vérification des mises à jour…"}'

echo "[auto-update] Nouvelle version disponible ($REMOTE_VERSION)..."

TEMP=$(mktemp "/tmp/hermes-desktop-XXXXXX.AppImage")
UPDATED=0

# ── Essayer zsync (delta) si zsync embarqué est disponible ──
ZSYNC="$APPDIR/usr/bin/zsync"
if [ -x "$ZSYNC" ]; then
    ZSYNC_URL="${RELEASE_URL}/${APPIMAGE_NAME}.zsync"
    _send_splash '{"status":"Téléchargement de la mise à jour…","details":"delta via zsync"}'
    echo "[auto-update] Téléchargement delta via zsync..."
    if "$ZSYNC" -i "$APPIMAGE" -o "$TEMP" "$ZSYNC_URL" 2>/dev/null; then
        chmod +x "$TEMP"
        mv "$TEMP" "$APPIMAGE"
        echo "[auto-update] Mise à jour delta terminée. Relance de l'application..."
        UPDATED=1
    else
        echo "[auto-update] Échec du delta, fallback téléchargement complet..."
    fi
fi

# ── Fallback: téléchargement complet via curl ──
if [ "$UPDATED" = "0" ]; then
    _send_splash '{"status":"Téléchargement de la mise à jour…","details":"téléchargement complet"}'
    echo "[auto-update] Téléchargement complet..."
    if curl -fSL --connect-timeout 30 --max-time 600 -o "$TEMP" "${RELEASE_URL}/${APPIMAGE_NAME}" 2>/dev/null; then
        chmod +x "$TEMP"
        mv "$TEMP" "$APPIMAGE"
        echo "[auto-update] Mise à jour terminée. Relance de l'application..."
        UPDATED=1
    else
        rm -f "$TEMP"
        echo "[auto-update] Échec du téléchargement."
    fi
fi

# ── Signaler la mise à jour à l'AppRun pour relance automatique ──
if [ "$UPDATED" = "1" ]; then
    _send_splash '{"status":"Redémarrage…","details":"Relance de la nouvelle version"}'
    mkdir -p "$(dirname "$CACHE_FILE")"
    echo "$REMOTE_VERSION" > "$CACHE_FILE"
    # Marker avec PID pour éviter les collisions entre instances
    touch /tmp/hermes-desktop-updated-$$
    sleep 1  # Laisser la splash afficher "Redémarrage…"
    exit 0
fi

_close_splash
