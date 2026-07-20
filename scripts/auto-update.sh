#!/usr/bin/env bash
# auto-update.sh — Delta update check via embedded appimageupdatetool
# Appelé en background par l'AppRun. L'outil lit l'updateinformation
# intégrée (gh-releases-zsync), compare via zsync, et applique
# le delta si une version plus récente est disponible.
set -e

UPDATE_TOOL="$APPDIR/usr/bin/appimageupdatetool"

# Pas une AppImage → rien à faire
if [ -z "${APPIMAGE:-}" ] || [ "$APPIMAGE" = "$APPDIR/AppRun" ]; then
    exit 0
fi

# Outil absent → rien à faire (ne devrait pas arriver)
if [ ! -x "$UPDATE_TOOL" ]; then
    exit 0
fi

# L'outil gère tout : zsync, comparaison checksum, delta update.
# Si pas de mise à jour, il exit 0 sans rien faire.
exec "$UPDATE_TOOL" "$APPIMAGE" "$@"
