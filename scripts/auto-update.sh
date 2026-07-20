#!/usr/bin/env bash
# auto-update.sh — Vérifie et applique les mises à jour de l'AppImage Hermes Desktop
# Injecté dans l'AppRun lors du post-processing.
#
# Utilise appimageupdatetool (téléchargé à la demande) pour des delta updates.
# Compatible avec le format gh-releases-zsync.

set -e

GITHUB_USER="elgabo86"
GITHUB_REPO="hermes-desktop"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/hermes-updater"
UPDATE_TOOL="$CACHE_DIR/appimageupdatetool"
UPDATE_TOOL_URL="https://github.com/AppImage/AppImageUpdate/releases/download/continuous/appimageupdatetool-x86_64.AppImage"

# ── Fonctions UI ──────────────────────────────────────────────

show_info() {
    local text="$1"
    if command -v zenity &>/dev/null; then
        LD_LIBRARY_PATH="" zenity --info --title="Hermes Desktop" --text="$text" --width=400 2>/dev/null
    elif command -v kdialog &>/dev/null; then
        LD_LIBRARY_PATH="" kdialog --title "Hermes Desktop" --msgbox "$text" 2>/dev/null
    elif command -v notify-send &>/dev/null; then
        notify-send "Hermes Desktop" "$text" --icon=system-software-update
    else
        echo "[Hermes] $text"
    fi
}

ask_update() {
    local version="$1"
    if command -v zenity &>/dev/null; then
        LD_LIBRARY_PATH="" zenity --question \
            --title="Mise à jour disponible" \
            --text="Hermes Desktop v${version} est disponible.\n\nVoulez-vous mettre à jour maintenant ?" \
            --ok-label="Mettre à jour" --cancel-label="Plus tard" \
            --width=400 2>/dev/null
    elif command -v kdialog &>/dev/null; then
        LD_LIBRARY_PATH="" kdialog --title "Mise à jour disponible" \
            --yesno "Hermes Desktop v${version} est disponible.\n\nVoulez-vous mettre à jour maintenant ?" \
            --yes-label "Mettre à jour" --no-label "Plus tard" 2>/dev/null
    else
        return 1  # no UI, skip
    fi
}

show_progress() {
    if command -v zenity &>/dev/null; then
        LD_LIBRARY_PATH="" zenity --progress \
            --title="Mise à jour..." \
            --text="$1" \
            --pulsate --auto-close --width=400 2>/dev/null &
        PROGRESS_PID=$!
    fi
}

hide_progress() {
    if [ -n "${PROGRESS_PID:-}" ]; then
        kill "$PROGRESS_PID" 2>/dev/null || true
        wait "$PROGRESS_PID" 2>/dev/null || true
    fi
}

download_tool() {
    echo "Téléchargement de l'outil de mise à jour..."
    mkdir -p "$CACHE_DIR"

    if command -v curl &>/dev/null; then
        curl -sSL --connect-timeout 30 "$UPDATE_TOOL_URL" -o "$UPDATE_TOOL.tmp"
    elif command -v wget &>/dev/null; then
        wget -q --timeout=30 "$UPDATE_TOOL_URL" -O "$UPDATE_TOOL.tmp"
    else
        echo "ERREUR: ni curl ni wget n'est disponible."
        return 1
    fi

    mv "$UPDATE_TOOL.tmp" "$UPDATE_TOOL"
    chmod +x "$UPDATE_TOOL"
    echo "Outil prêt."
}

# ── Vérification de mise à jour ────────────────────────────────

check_and_update() {
    # On ne vérifie que si on est une vraie AppImage
    if [ -z "${APPIMAGE:-}" ] || [ "$APPIMAGE" = "$APPDIR/AppRun" ]; then
        return 0
    fi

    # Récupérer la version actuelle depuis le nom du fichier
    local current_version
    current_version=$(echo "$(basename "$APPIMAGE")" | sed -n 's/^hermes-desktop-\([0-9.]*\)-x86_64.*/\1/p')
    if [ -z "$current_version" ]; then
        return 0
    fi

    # Récupérer la dernière release via l'API GitHub
    echo "Vérification des mises à jour..."
    local latest_json
    latest_json=$(curl -sS --connect-timeout 10 \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/${GITHUB_USER}/${GITHUB_REPO}/releases/latest" 2>/dev/null || true)

    if [ -z "$latest_json" ]; then
        return 0  # Pas de réseau, on ignore silencieusement
    fi

    # Extraire la date de publication et l'URL de l'asset zsync
    local published_at
    published_at=$(echo "$latest_json" | grep -oP '"published_at":\s*"\K[^"]+' | head -1)
    local zsync_url
    zsync_url=$(echo "$latest_json" | grep -oP '"browser_download_url":\s*"\K[^"]*\.zsync' | head -1)

    if [ -z "$published_at" ] || [ -z "$zsync_url" ]; then
        return 0
    fi

    # Télécharger le .zsync le plus récent pour comparer les checksums
    local remote_zsync
    remote_zsync=$(curl -sS --connect-timeout 10 "$zsync_url" 2>/dev/null || true)
    if [ -z "$remote_zsync" ]; then
        return 0
    fi

    # Extraire le SHA-1 du .zsync distant
    local remote_sha
    remote_sha=$(echo "$remote_zsync" | grep -oP 'SHA1=\K[a-f0-9]+' | head -1)
    if [ -z "$remote_sha" ]; then
        return 0
    fi

    # Calculer le SHA-1 de l'AppImage locale (seules les 16 premières lignes, rapide)
    local local_sha
    local_sha=$(head -c 1048576 "$APPIMAGE" 2>/dev/null | sha1sum | awk '{print $1}')
    local local_full_sha
    local_full_sha=$(sha1sum "$APPIMAGE" 2>/dev/null | awk '{print $1}')

    # Comparer les checksums
    if [ "$local_full_sha" = "$remote_sha" ]; then
        echo "Hermes Desktop est à jour (v${current_version})."
        return 0
    fi

    # Une mise à jour est disponible
    local tag_name
    tag_name=$(echo "$latest_json" | grep -oP '"tag_name":\s*"v?\K[^"]+' | head -1)
    echo "Nouvelle version disponible (${tag_name:-$current_version}, $(echo "$published_at" | cut -dT -f1))"

    if ! ask_update "${tag_name:-$current_version}"; then
        echo "Mise à jour repoussée."
        return 0
    fi

    # Télécharger l'outil si nécessaire
    if [ ! -x "$UPDATE_TOOL" ]; then
        download_tool || {
            hide_progress
            show_info "Impossible de télécharger l'outil de mise à jour.\nVeuillez réessayer plus tard."
            return 1
        }
    fi

    # Lancer la mise à jour (delta via zsync)
    echo "Mise à jour en cours..."
    show_progress "Téléchargement de la mise à jour..."

    "$UPDATE_TOOL" "$APPIMAGE" && {
        hide_progress
        echo "✅ Mise à jour terminée. L'application va redémarrer."
        show_info "Mise à jour terminée !\n\nHermes Desktop va redémarrer avec la nouvelle version."
        exec "$APPIMAGE" "$@"
        exit 0
    } || {
        hide_progress
        echo "❌ Échec de la mise à jour."
        show_info "La mise à jour a échoué.\n\nVous pouvez réessayer plus tard ou télécharger\nla nouvelle version manuellement depuis GitHub."
        return 0
    }
}

# ── Entry point ─────────────────────────────────────────────────

check_and_update "$@"
