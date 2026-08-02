# Hermes Desktop — AppImage FR

Build d'AppImage Hermes Desktop avec trad française, distribué via elgabo86/hermes-desktop.

## Architecture

- **Source** : fork elgabo86/hermes-agent, branche `i18n/french-desktop`
- **Plus de patches** — le fork contient directement fr.ts, composants modifiés, types/en/zh/catalog/languages
- **Script** : `build-appimage.sh` clone le fork i18n → build → AppImage
- **Une seule source de vérité** : le fork i18n = PR #48070 = AppImage
- **Auto-update** : extrait le timestamp du nom du fichier AppImage → curl `releases/latest/download/VERSION` → compare → télécharge si différent. Splash Electron pendant le téléchargement + relance automatique après update. Pas de cache externe.

## Auto-update et splash

### Mécanisme

1. L'AppRun lance `usr/bin/auto-update` (synchrone) avant de démarrer Hermes
2. L'auto-update compare `build-version` (embarqué) avec `VERSION` distant
3. Si différent : splash Electron + téléchargement (zsync delta, fallback curl)
4. Si update réussi : marker `/tmp/hermes-desktop-updated-$$` créé
5. L'AppRun détecte le marker et `exec` la nouvelle AppImage au lieu de l'ancienne

### Splash Electron

La splash est un mini-app Electron embarquée dans `usr/share/hermes/splash/` :
- **Hardlink** du binaire `Hermes` (même inode, zéro duplication)
- **Mini `resources/app.asar`** (~5 Ko) avec `package.json` + `splash.js` + `splash.html`
- Electron résout `resources/app.asar` relativement à `/proc/self/exe` → le hardlink charge notre splash
- **Symlinks** vers les libs Electron du parent (`.so`, `.pak`, `locales/`, etc.)
- Communication via FIFO : l'auto-update envoie du JSON ligne par ligne, la splash affiche

Fichiers : `splash/package.json`, `splash/splash.js`, `splash/splash.html`

### Construction de l'asar splash

Au post-processing, `npx @electron/asar pack` construit le mini-asar.
Pas d'outil custom — le format asar est généré par l'outil officiel.

## Workflow de mise à jour

```bash
# 1. Rebase le fork i18n sur upstream/main
cd /var/ssdtemp/hermeswork/hermes-i18n-fr
git fetch upstream
git rebase upstream/main
# Résoudre les conflits, corriger TSC, commit

# 2. Push la branche i18n (met à jour le PR #48070)
git push --force-with-lease origin i18n/french-desktop

# 3. L'AppImage se rebuild automatiquement (CI quotidien à 06:00 UTC)
#    Ou déclencher manuellement :
gh workflow run "Build AppImage" --repo elgabo86/hermes-desktop
```

## CI

- Workflow : `.github/workflows/build.yml`
- Schedule : tous les jours à 06:00 UTC
- Release : tag `latest` écrasé à chaque build, avec AppImage + zsync + VERSION

## Fork i18n

- Repo : elgabo86/hermes-agent, branche `i18n/french-desktop`
- PR : https://github.com/NousResearch/hermes-agent/pull/48070
- Doit être maintenu rebasé sur upstream/main

## Fichiers modifiés dans le fork (par rapport à upstream)

| Fichier | Modification |
|---|---|
| `i18n/fr.ts` | Traduction française complète (`defineLocale`) |
| `i18n/catalog.ts` | Import + registre `fr` |
| `i18n/languages.ts` | Option FR, aliases, regex régions |
| `i18n/types.ts` | `'fr'` dans Locale, `staleAuxWarning`, `uninstall`, `billing`, `toggleLayoutEditMode` |
| `i18n/en.ts` | `staleAuxWarning`, `uninstall`, `billing`, `themeSearchPlaceholder` |
| `i18n/zh.ts` | `staleAuxWarning`, `uninstall`, `billing`, `themeSearchPlaceholder`, `toggleLayoutEditMode` |
| `components/chat/intro.tsx` | Chargement `intro-copy.fr.jsonl` |
| `components/chat/intro-copy.fr.jsonl` | Messages d'intro en français |
| `components/gateway-connecting-overlay.tsx` | i18n CONNECTING |
| `app/settings/uninstall-section.tsx` | i18n zone dangereuse |
| `app/settings/billing/*` | i18n facturation (4 composants) |
| `app/settings/appearance-settings.tsx` | i18n placeholder recherche thèmes |
| `app/contrib/controller.tsx` | i18n toggle layout edit mode |
| `i18n/languages.test.ts` | Tests regex FR |
| `i18n/runtime.test.ts` | Tests résolution FR |

## Pièges

- `defineLocale()` masque les clés manquantes → toujours vérifier avec `compare-i18n-keys.py` après rebase
- `npm run build` utilise Vite (pas de type-check) → toujours `npx tsc --noEmit` avant de pusher
- `elgabo86/hermes-desktop` ne contient QUE le script de build + CI — pas de duplication i18n
- Les `fieldLabels`/`fieldDescriptions` utilisent des clés préfixées (`desktop.repoScan*`) → respecter le prefixe dans `defineFieldCopy`
- **Ne pas utiliser `--app-path`** avec le binaire Electron packagé — il cherche toujours `resources/app.asar` relativement à `/proc/self/exe`, pas au flag. La splash utilise un hardlink + resources/ dédié à la place.
- **Format asar custom** : ne pas réinventer la sérialisation asar (header Pickle Chromium). Utiliser `npx @electron/asar pack` — l'outil officiel.
- **FIFO splash** : ouvrir en lecture-écriture (`exec 3<>`) sinon `open()` bloque jusqu'à ce qu'un reader se connecte.
