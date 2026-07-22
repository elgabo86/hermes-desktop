# Hermes Desktop — AppImage FR

Build d'AppImage Hermes Desktop avec trad française, distribué via elgabo86/hermes-desktop.

## Architecture

- **Source** : upstream NousResearch/hermes-agent (main)
- **Patches** : `patches/french-files.patch` + `patches/upstream-files.patch`
- **Nouveaux fichiers** : `patches/fr.ts` + `patches/intro-copy.fr.jsonl` (copiés avant les patches)
- **Script** : `build-appimage.sh` clone upstream → copie nouveaux fichiers → applique patches → build

## Patches

### french-files.patch
Fichiers modifiés pour la locale française :
- `i18n/catalog.ts` — import + registre `fr`
- `i18n/languages.ts` — option FR, aliases, regex régions
- `i18n/types.ts` — `'fr'` dans Locale, `connectingPrefix/Tail`, section `uninstall`
- `i18n/context.tsx` — persistance localStorage
- `components/chat/intro.tsx` — chargement intro-copy.fr.jsonl
- `components/gateway-connecting-overlay.tsx` — i18n CONNECTING
- `app/settings/uninstall-section.tsx` — i18n zone dangereuse
- `i18n/languages.test.ts` — tests regex FR

### upstream-files.patch
Ajouts minimaux à en.ts et zh.ts :
- `connectingPrefix: 'CONN'` / `connectingTail: 'ECTING'` (section boot)
- Section `uninstall` complète

### fr.ts
Traduction française complète — implémente l'interface `Translations` directement.
Si des clés manquent → erreur TypeScript au build.

## Mise à jour des patches

Quand upstream évolue et que les patches cassent :

```bash
# 1. Cloner upstream frais
git clone --depth=1 https://github.com/NousResearch/hermes-agent.git /tmp/upstream

# 2. Copier les fichiers FR
cp patches/fr.ts /tmp/upstream/apps/desktop/src/i18n/
cp patches/intro-copy.fr.jsonl /tmp/upstream/apps/desktop/src/components/chat/

# 3. Appliquer les patches existants pour voir ce qui casse
cd /tmp/upstream
git apply ~/HermesWork/hermes-desktop/patches/french-files.patch
git apply ~/HermesWork/hermes-desktop/patches/upstream-files.patch

# 4. Si échec → appliquer les changements manuellement
#    (modifier catalog.ts, types.ts, languages.ts, en.ts, zh.ts, etc.)

# 5. Build pour vérifier
cd apps/desktop && npm install --ignore-scripts && npm run build

# 6. Régénérer les patches
cd /tmp/upstream
git diff -- apps/desktop/src/i18n/catalog.ts apps/desktop/src/i18n/languages.ts \
  apps/desktop/src/i18n/types.ts apps/desktop/src/i18n/context.tsx \
  apps/desktop/src/components/chat/intro.tsx \
  apps/desktop/src/components/gateway-connecting-overlay.tsx \
  apps/desktop/src/app/settings/uninstall-section.tsx \
  apps/desktop/src/i18n/languages.test.ts \
  > ~/HermesWork/hermes-desktop/patches/french-files.patch

git diff -- apps/desktop/src/i18n/en.ts apps/desktop/src/i18n/zh.ts \
  > ~/HermesWork/hermes-desktop/patches/upstream-files.patch

# 7. Copier fr.ts mis à jour
cp apps/desktop/src/i18n/fr.ts ~/HermesWork/hermes-desktop/patches/

# 8. Commit + push
cd ~/HermesWork/hermes-desktop
git add -A && git commit -m "fix: regenerate patches for upstream <version>"
git push
```

## CI

- Workflow : `.github/workflows/build.yml` (Build AppImage)
- Schedule : tous les 2 jours à 06:00 UTC
- Déclenchement manuel : `gh workflow run "Build AppImage" --repo elgabo86/hermes-desktop`
- Release : l'AppImage est uploadée en release GitHub avec tag de version

## Fork i18n

- Repo : elgabo86/hermes-agent, branche `i18n/french-desktop`
- Sert de référence pour les fichiers FR
- Doit être maintenu à jour (rebase sur upstream/main périodiquement)

## Pièges

- `npm run build` utilise Vite (pas de type-check) → **toujours vérifier avec `npx tsc --noEmit` avant de publier**
- `fr.ts` implémente `Translations` directement → toute clé manquante = crash runtime, pas juste de l'anglais
- `defineLocale()` n'est PAS utilisé (contrairement à ce que suggère le commit dbd97c5b0)
- Les nouveaux fichiers (fr.ts, intro-copy.fr.jsonl) ne sont PAS dans les patches git diff → copiés séparément
- `build-appimage.sh` doit être mis à jour si on ajoute de nouveaux fichiers
- Le CI a besoin de `contents: write` pour créer les releases
