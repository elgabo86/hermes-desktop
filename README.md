# Hermes Desktop — AppImage FR

AppImage non-officielle de [Hermes Desktop](https://github.com/NousResearch/hermes-agent) avec traduction française complète.

- 🇫🇷 Interface entièrement en français
- 🔄 Auto-update automatique au lancement

## Pourquoi ?

L'AppImage officielle n'inclut pas la locale française. Ce repo reconstruit
Hermes Desktop directement depuis le fork [elgabo86/hermes-agent](https://github.com/elgabo86/hermes-agent)
(branche `i18n/french-desktop`, PR [#48070](https://github.com/NousResearch/hermes-agent/pull/48070)).

## Utilisation

```bash
curl -LO "https://github.com/elgabo86/hermes-desktop/releases/latest/download/hermes-desktop-*-x86_64.AppImage"
chmod +x hermes-desktop-*.AppImage
./hermes-desktop-*.AppImage
```

Pas de sudo nécessaire.

## Auto-update

Au lancement, l'AppImage télécharge `VERSION` depuis la release et compare
avec un cache local. Si différent, elle télécharge la nouvelle AppImage avant
de démarrer.

## Build

```bash
./build-appimage.sh
```

Build automatique quotidien à 06:00 UTC via GitHub Actions.

## License

Hermes Agent est sous [Apache 2.0](https://github.com/NousResearch/hermes-agent/blob/main/LICENSE).
