# Dontype (丝语)

[English](README.md) · [中文](README.zh.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Español](README.es.md) · **Français**

Dictée vocale et lecture à voix haute respectueuses de la vie privée pour Mac, par **Easylii**.
Marque occidentale **Dontype** (don't type — parlez, tout simplement), marque chinoise **丝语**. Appuyez deux fois sur **Control** pour commencer à parler, une fois pour arrêter — transcription locale, nettoyage par IA, collage automatique au niveau du curseur. Tout s'exécute sur l'appareil ; votre voix ne quitte jamais votre Mac.

## Points forts

- **3 en 1.** Voix → texte (dictée), texte → voix (lecture à voix haute du texte sélectionné) et un historique de presse-papiers à 5 emplacements — trois outils dans une seule app de la barre de menus. La plupart des outils de dictée n'en font qu'un.
- **Aucune API facturée à l'usage, aucun abonnement supplémentaire.** La reconnaissance s'exécute entièrement **en local** (gratuite, hors ligne, sans consommation de bande passante). Le nettoyage par IA s'appuie sur le **Claude Code / Codex que vous possédez déjà**, via leur CLI — pas de clé d'API Anthropic distincte et pas de facturation à l'usage par jeton. Rien de plus à payer ; sans l'un ou l'autre, il se contente de produire la transcription brute (toujours gratuite).
- **Historique de presse-papiers à 5 emplacements.** Chaque résultat de dictée et chaque copie manuelle alimente un historique de 5 éléments (dédoublonné, étiqueté par source) — cliquez sur n'importe lequel pour le recopier. En mémoire uniquement, les éléments sensibles sont ignorés.

## Comment ça fonctionne

```
Double-tap Control to record (tap to stop / Esc = stop without paste)
  → whisper.cpp local recognition (offline; falls back to Apple speech if no model)
  → AI cleanup (Claude API / Claude Code / Codex, auto-fallback; rewrites into fluent sentences)
  → floating result window + copy button
  → auto-paste into the field you were in
```

## Démo

**Voix → texte** — appuyez deux fois sur Control, parlez, le texte est collé au niveau de votre curseur :

![Démo voix vers texte](design/demo-stt.svg)

**Texte → voix** — sélectionnez du texte, appuyez deux fois sur le ⌘ droit, une voix le lit à voix haute :

![Démo texte vers voix](design/demo-tts.svg)

**Historique de presse-papiers** — vos 5 derniers extraits (dictées + copies manuelles), cliquez sur l'un pour le recopier :

![Démo de l'historique de presse-papiers](design/demo-clipboard.svg)

**Parcours d'installation interactif** — ouvrez [`design/dontype-install-flow.html`](design/dontype-install-flow.html) dans un navigateur pour vivre l'intégralité de la première utilisation (8 écrans : Bienvenue → consentement à la vie privée → autorisations → modèle → raccourci → lecture à voix haute → IA → terminé).

> Les deux démos ci-dessus sont des SVG animés (ils s'animent dans le README). Pour le rendu réel, enregistrez de courts GIF de l'application avec `Cmd+Shift+5` → Gifski / Kap ; une fois le dépôt public, vous pouvez aussi héberger le parcours HTML via GitHub Pages.

## Langues de reconnaissance prises en charge

> **Point essentiel : il n'existe pas de « packs de reconnaissance par langue ».** Un seul modèle whisper couvre environ 99 langues — il suffit de définir la langue ou d'utiliser la détection automatique. Vous ne téléchargez jamais plusieurs modèles, un par langue.

**Détection automatique par défaut** (`recognitionLang: auto`) — il devine ce que vous parlez, aucun choix manuel n'est nécessaire. Le menu déroulant de la langue de reconnaissance ne liste que les langues **mises en avant** pour un verrouillage manuel :

| Niveau | Langues | Remarques |
|------|-----------|-------|
| **Mises en avant** (dans le menu déroulant, officiellement prises en charge) | English · Chinese (Mandarin) · 日本語 · 한국어 · Spanish · French · German · Italian · Portuguese | turbo ≈ large-v3 complet ; sans risque à annoncer |
| Fonctionnent, avec réserves | Cantonese · Thai · Vietnamese, etc. | turbo se dégrade nettement sur le cantonais/thaï → basculez `whisperModel` sur `large-v3` ; absentes du menu déroulant, mais la détection automatique les reconnaît tout de même |
| Faibles (non annoncées) | langues peu dotées | taux d'erreur plus élevé, sujettes aux hallucinations |

- **turbo vs large-v3** : le `large-v3-turbo` par défaut est rapide et ≈ de qualité complète pour les langues bien dotées ; il faiblit sur celles qui le sont peu (notamment le cantonais, le thaï). Basculez `whisperModel` sur `large-v3` pour une meilleure précision multilingue.
- **La langue de l'interface** (menus / assistant) est distincte de la reconnaissance — actuellement le chinois / l'anglais, avec repli sur l'anglais ailleurs. Une interface en japonais / coréen, etc. pourra être ajoutée progressivement lorsqu'un marché justifiera le travail de traduction.

## Installation

**Installation distribuée (recommandée)** : `./make-dmg.sh` génère `Dontype.dmg` (intégrant `install.command` / `PRIVACY.md` / les notes d'installation). Pour installer, faites un clic droit sur **install.command** à l'intérieur du DMG → « Ouvrir » ; le script copie vers `/Applications`, retire la quarantaine (le double-clic fonctionne ensuite), écrit une configuration par défaut et lance l'application.

**Premier lancement = assistant de configuration paginé** : Bienvenue → **Politique de confidentialité (acceptation obligatoire pour continuer)** → Autorisations → Modèle → Raccourci → Lecture à voix haute → IA → Terminé. Ensuite, « Réglages » dans la barre de menus ouvre un **panneau de réglages à fenêtre unique** (et non plus le flux paginé).

**Développement local** :

```bash
cd ~/Documents/SiYu
./build-app.sh          # build + bundle + sign → SiYu.app
open SiYu.app
```

> Remarque : le bundle de l'application porte toujours le nom `SiYu.app` en interne, mais le Finder / les autorisations / les menus affichent la marque **Dontype** (systèmes anglophones) / **丝语** (systèmes chinois), via la localisation `Info.plist` + `Resources/*.lproj`.
> Le certificat de signature se trouve dans `.cert/` (**pas dans le dépôt** — sauvegardez-le séparément). Un certificat fixe maintient valides l'Accessibilité et les autres autorisations TCC d'une recompilation à l'autre.

Après le lancement, un **logo en bulle** apparaît dans la barre de menus ; il devient rouge plein pendant l'enregistrement, orange plein pendant le nettoyage.

## Historique de presse-papiers (jusqu'à 5)

La section « Saisie vocale » de la barre de menus dispose d'un **historique de presse-papiers** — jusqu'à 5 entrées, cliquez pour recopier dans le presse-papiers :
- Deux sources, repérées par une icône : 🌊 les transcriptions de cette application / 📋 ce que vous avez copié manuellement.
- **Dédoublonnage automatique** : un contenu identique n'est conservé qu'une fois et remonté en tête.
- **En mémoire uniquement, jamais écrit sur le disque, effacé à la fermeture** ; les éléments de presse-papiers signalés comme sensibles par les gestionnaires de mots de passe sont **ignorés**.

## Lire à voix haute le texte sélectionné (sens inverse)

Dans **n'importe quelle application**, sélectionnez du texte (ou placez le curseur au début) → **appuyez deux fois sur le ⌘ droit** → une voix Premium lit **de cet endroit jusqu'à la fin du bloc de texte courant** (hors ligne, gratuit). Pendant la lecture : **appuyez une fois sur le ⌘ droit** pour mettre en pause/reprendre, **Esc** pour arrêter.
- Lecture vers le bas : il tente d'abord d'utiliser l'Accessibilité pour obtenir « le texte complet du champ ciblé + la position de la sélection », lisant du début de la sélection jusqu'à la fin de ce bloc de texte ; s'il n'y parvient pas (certaines pages web / terminaux / Electron), il se rabat sur la **lecture de la seule portion sélectionnée**.
- Repli par sélection : lorsque l'Accessibilité ne peut pas obtenir la sélection, il synthétise un Cmd+C, lit le presse-papiers, puis le **restaure**.
- Réglages : configurez la voix / le débit / la touche de déclenchement / l'aperçu sous le panneau de réglages « ⑧ Lire la sélection à voix haute → Configurer » ; si vous n'avez aucune voix Premium, un point d'accès permet d'en télécharger une dans les Réglages Système.

## Confidentialité

Votre voix ne quitte jamais l'appareil — zéro collecte, zéro suivi, aucun compte, aucune télémétrie. Le nettoyage par IA optionnel n'envoie que du **texte** (pas d'audio) au compte Claude/Codex **que vous configurez vous-même**. Politique complète dans [`PRIVACY.md`](PRIVACY.md) (bilingue, niveau RGPD / CCPA). Le premier lancement comporte une étape de consentement à la vie privée.

## Configuration

Le moteur de nettoyage par IA est sélectionné automatiquement par ordre de priorité : `Claude API (fastest) → Claude Code → Codex → raw passthrough`, avec repli automatique en cas d'échec. Pour l'API la plus rapide : définissez `ANTHROPIC_API_KEY`, ou indiquez `apiKey` dans `~/.config/siyu/config.json`. Il fonctionne aussi sans clé : avec Claude Code / Codex, il utilise votre abonnement ; sans rien, il produit la transcription brute.

Champs de `~/.config/siyu/config.json` :

| Champ | Signification | Valeur par défaut |
|-------|---------|---------|
| `apiKey` | clé d'API Anthropic | vide (se rabat sur la variable d'environnement) |
| `model` | modèle pour le nettoyage par API | `claude-haiku-4-5-20251001` |
| `cleanup` | activer le nettoyage par IA (déclenché automatiquement uniquement quand des hésitations sont détectées) | `true` |
| `autoPaste` | coller automatiquement au curseur après un résultat | `true` |
| `whisperModel` | id du modèle whisper (`large-v3-turbo` / `large-v3` / `medium` / `small`) | `large-v3-turbo` |
| `recognitionLang` | langue de reconnaissance (`auto` / `en` / `zh` / `ja` / `ko` / `es` / `fr` / `de` / `it` / `pt`) | `auto` |
| `uiLang` | langue de l'interface (`auto` / `zh` / `en`) | `auto` |
| `readKey` | touche de déclenchement de la lecture à voix haute (`control`/`fn`/`rightCommand`/`rightOption`/`option`) | `rightCommand` |
| `readVoice` | id de la voix de lecture à voix haute (vide = sélection automatique d'une voix Premium selon la langue du texte) | vide |
| `readRate` | débit de la lecture à voix haute 0…1 | `0.5` |

## Structure

| Fichier | Responsabilité |
|------|----------------|
| `AppDelegate.swift` | barre de menus, orchestration du flux, historique de presse-papiers, autorisations |
| `HotkeyMonitor.swift` | détection globale de la double frappe d'une touche de modification (CGEventTap) |
| `Dictation.swift` | enregistrement + reconnaissance (whisper d'abord, repli Apple) |
| `Whisper.swift` | backend whisper.cpp : dossier des modèles, langue de reconnaissance, serveur résident |
| `Cleaner.swift` | nettoyage par IA (chaîne de repli API / Claude Code / Codex ; réécrit en phrases) |
| `ModelDownloader.swift` | téléchargement du modèle whisper (rappels de progression vers l'assistant) |
| `TextGrabber.swift` | récupération du texte sélectionné (Accessibilité directe + repli Cmd+C avec restauration du presse-papiers) |
| `Speaker.swift` | moteur de lecture à voix haute (AVSpeechSynthesizer + voix Premium, sélection automatique selon la langue) |
| `HotkeySetup.swift` / `ReadSetup.swift` | raccourci de démarrage/arrêt, configuration de la lecture à voix haute (test de double frappe pour confirmer) |
| `Onboarding.swift` | **assistant paginé** de première utilisation (avec consentement à la vie privée) + **panneau de réglages** du menu (deux modes, une seule classe) |
| `RecallStore.swift` | historique de presse-papiers (jusqu'à 5, dédoublonnage, en mémoire, ignore les éléments sensibles) |
| `IconRenderer.swift` | icône de barre de menus + icônes de source du micro (chemins SVG dessinés à l'exécution) |
| `HUD.swift` | fenêtre de résultat flottante / pilule déplaçable / forme d'onde de la lecture à voix haute |
| `Paster.swift` | presse-papiers + Cmd+V synthétique |
| `L.swift` | localisation de l'interface (zh/en) · `Config.swift` configuration à l'exécution |

`design/dontype-install-flow.html` est le prototype interactif du flux d'installation (pour la démo).

## Feuille de route

- **Reconnaissance en flux continu** : le texte au fur et à mesure que vous parlez (whisper-server est déjà résident ; il peut faire du streaming par segments).
- **Accélération CoreML** : activer CoreML pour l'encodeur whisper.
- **Notarisation Developer ID** : passer à une signature + notarisation pour supprimer le « clic droit → Ouvrir » du premier lancement.
