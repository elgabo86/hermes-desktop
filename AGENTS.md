# Hermes Desktop — AppImage FR

Build d'AppImage Hermes Desktop avec trad française, distribué via elgabo86/hermes-desktop.

## Architecture

- **Source** : fork elgabo86/hermes-agent, branche `i18n/french-desktop`
- **Plus de patches** — le fork contient directement fr.ts, composants modifiés, types/en/zh/catalog/languages
- **Script** : `build-appimage.sh` clone le fork i18n → build → AppImage
- **Une seule source de vérité** : le fork i18n = PR #48070 = AppImage

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

- Workflow : `.github/workflows/build.yml` (Build AppImage)
- Schedule : tous les jours à 06:00 UTC
- Déclenchement manuel : `gh workflow run "Build AppImage" --repo elgabo86/hermes-desktop`
- Release : l'AppImage est uploadée en release GitHub avec tag de version

## Fork i18n

- Repo : elgabo86/hermes-agent, branche `i18n/french-desktop`
- PR : https://github.com/NousResearch/hermes-agent/pull/48070
- Source unique de vérité pour toutes les modifs françaises
- Doit être maintenu rebasé sur upstream/main périodiquement

## Fichiers modifiés dans le fork (par rapport à upstream)

| Fichier | Modification |
|---|---|
| `i18n/fr.ts` | Traduction française complète (`defineLocale`) |
| `i18n/catalog.ts` | Import + registre `fr` |
| `i18n/languages.ts` | Option FR, aliases, regex régions |
| `i18n/types.ts` | `'fr'` dans Locale, `staleAuxWarning`, section `uninstall` |
| `i18n/en.ts` | `staleAuxWarning`, section `uninstall` |
| `i18n/zh.ts` | `staleAuxWarning`, section `uninstall` |
| `components/chat/intro.tsx` | Chargement `intro-copy.fr.jsonl` |
| `components/chat/intro-copy.fr.jsonl` | Messages d'intro en français |
| `components/gateway-connecting-overlay.tsx` | i18n CONNECTING |
| `app/settings/uninstall-section.tsx` | i18n zone dangereuse |
| `i18n/languages.test.ts` | Tests regex FR |
| `i18n/runtime.test.ts` | Tests résolution FR |

## Pièges

- Le fork utilise `defineLocale()` → les clés manquantes héritent de l'anglais sans erreur TSC. Toujours vérifier les sections upstream absentes après rebase.
- `npm run build` utilise Vite (pas de type-check) → **toujours vérifier avec `npx tsc --noEmit` avant de pusher**
- `elgabo86/hermes-desktop` ne contient QUE le script de build + CI — pas de duplication i18n
