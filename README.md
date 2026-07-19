# Hermes Desktop — AppImage Build

Unofficial AppImage of [Hermes Desktop](https://github.com/NousResearch/hermes-agent) with custom modifications:

- 🇫🇷 Full **French** locale (UI translation)
- 🔤 Native context menus in French (Chromium)
- 🧹 Uninstall section in French

## Why?

The official AppImage doesn't include the French locale. This repo rebuilds
Hermes Desktop with patches from the fork [elgabo86/hermes-agent](https://github.com/elgabo86/hermes-agent)
(`i18n/french-desktop` branch, PR [#48070](https://github.com/NousResearch/hermes-agent/pull/48070)).

## Usage

```bash
# Download latest release
curl -LO "https://github.com/elgabo86/hermes-desktop/releases/latest/download/Hermes.AppImage"
chmod +x Hermes.AppImage
./Hermes.AppImage
```

**No sudo needed** — the AppImage handles Electron's sandbox internally.

## Updates

L'AppImage intègre un **auto-updater** qui vérifie les mises à jour au lancement.
Si une nouvelle version est disponible :
- **Delta update** automatique (quelques Mo au lieu de 135 Mo) grâce à [AppImageUpdate](https://github.com/AppImage/AppImageUpdate)
- Une boîte de dialogue propose la mise à jour (zenity/kdialog)
- L'AppImage se met à jour toute seule et redémarre

L'outil de mise à jour (`appimageupdatetool`) est téléchargé automatiquement à la première
mise à jour et mis en cache dans `~/.cache/hermes-updater/`.

**Avec AppImageLauncher** (optionnel) : si vous avez [AppImageLauncher](https://github.com/TheAssassin/AppImageLauncher)
installé, il gère les mises à jour automatiquement en arrière-plan — rien à configurer.

## Manual build

```bash
./build-appimage.sh [upstream_ref]
```

Requires: Node.js 22+, npm, git.

## License

Hermes Agent is [Apache 2.0](https://github.com/NousResearch/hermes-agent/blob/main/LICENSE).
Patches in this repo follow the same license.
