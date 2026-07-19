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

The AppImage is NOT auto-updated by Hermes Desktop's built-in updater.
To update, download the latest release.

## Manual build

```bash
./build-appimage.sh [upstream_ref]
```

Requires: Node.js 22+, npm, git.

## License

Hermes Agent is [Apache 2.0](https://github.com/NousResearch/hermes-agent/blob/main/LICENSE).
Patches in this repo follow the same license.
