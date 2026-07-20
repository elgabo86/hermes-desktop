# Hermes Desktop — AppImage Build

Unofficial AppImage of [Hermes Desktop](https://github.com/NousResearch/hermes-agent) with custom modifications:

- 🇫🇷 Fully translated in French (UI, context menus, uninstall)
- 🔄 Auto-update with delta updates

## Why?

The official AppImage doesn't include the French locale. This repo rebuilds
Hermes Desktop with patches from the fork [elgabo86/hermes-agent](https://github.com/elgabo86/hermes-agent)
(`i18n/french-desktop` branch, PR [#48070](https://github.com/NousResearch/hermes-agent/pull/48070)).

## Usage

```bash
# Download latest release
curl -LO "https://github.com/elgabo86/hermes-desktop/releases/latest/download/hermes-desktop-*-x86_64.AppImage"
chmod +x hermes-desktop-*.AppImage
./hermes-desktop-*.AppImage
```

**No sudo needed** — the AppImage handles Electron's sandbox internally.

## Auto-update

The AppImage embeds [appimageupdatetool](https://github.com/AppImage/AppImageUpdate)
directly. On launch, it silently checks for updates in the background:

- **Delta update** — only downloads changed chunks (a few MB, not 135 MB)
- **No prompts, no API calls** — the tool compares checksums via zsync
- If an update is found, it applies the delta and restarts
- If already up to date, it exits silently (zero overhead)

Nothing to install, nothing to configure. The update information is embedded
in the AppImage at build time.

## Builds

**Automated**: GitHub Actions builds daily at 06:00 UTC (plus `workflow_dispatch`).

**Manual**:
```bash
./build-appimage.sh [upstream_ref]
```

Requires: Node.js 22+, npm, git, squashfs-tools, zsync.

If the French patch fails to apply (upstream divergence), the build fails
— no silent broken AppImages.

## License

Hermes Agent is [Apache 2.0](https://github.com/NousResearch/hermes-agent/blob/main/LICENSE).
Patches in this repo follow the same license.
