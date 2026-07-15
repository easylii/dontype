# Dontype (丝语)

[English](README.md) · [中文](README.zh.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Español](README.es.md) · **Français**

**Le compagnon vocal ultime pour le vibe coding sur Mac**, par **Easylii**. Marque occidentale **Dontype** (don't type — parlez, tout simplement), marque chinoise **丝语**.

Le vibe coding, c'est *parler* à votre IA, pas tout taper. Dontype fait écouter votre Mac : dictez vos prompts directement dans **Claude Code, Cursor ou n'importe quel champ** — appuyez deux fois sur **Control**, parlez, et il transcrit en local, retire les hésitations et colle au niveau du curseur ; un bouton l'**envoie**. Faites tourner toute la boucle **sans les mains depuis une télécommande Apple TV**, et faites-vous **relire** les réponses. Tout s'exécute sur l'appareil ; votre voix ne quitte jamais votre Mac.

## Points forts

- **Conçu pour le vibe coding.** Dictez vos prompts directement dans Claude Code, Cursor, ChatGPT ou n'importe quel champ de texte — dictez, il supprime les « euh », corrige la grammaire, colle au niveau du curseur, et un bouton l'**envoie** (Entrée). Détendez-vous et faites tourner toute la boucle depuis une télécommande Apple TV.
- **3 en 1.** Voix → texte (dictée), texte → voix (lecture à voix haute du texte sélectionné) et un historique de presse-papiers à 5 emplacements — trois outils dans une seule app de la barre de menus. La plupart des outils de dictée n'en font qu'un.
- **Aucune API facturée à l'usage, aucun abonnement supplémentaire.** La reconnaissance s'exécute entièrement **en local** (gratuite, hors ligne, sans consommation de bande passante). Le nettoyage par IA s'appuie sur le **Claude Code / Codex que vous possédez déjà**, via leur CLI — pas de clé d'API Anthropic distincte et pas de facturation à l'usage par jeton. Rien de plus à payer ; sans l'un ou l'autre, il se contente de produire la transcription brute (toujours gratuite).
- **Historique de presse-papiers à 5 emplacements.** Chaque résultat de dictée et chaque copie manuelle alimente un historique de 5 éléments (dédoublonné, étiqueté par source) — cliquez sur n'importe lequel pour le recopier. En mémoire uniquement, les éléments sensibles sont ignorés.
- **Compatible avec la télécommande Apple TV (2ᵉ ou 3ᵉ génération).** Dictez sans les mains depuis l'autre bout de la pièce avec une Siri Remote : appuyez sur **TV** pour commencer à parler, **TV** à nouveau pour terminer, **OK** pour envoyer, **Back ‹ / Esc** pour annuler, faites glisser le **pavé tactile** pour déplacer le curseur, et les **flèches** agissent comme la touche Tab entre les contrôles. Configurez-la dans la page Télécommande de l'assistant de configuration (une démo animée montre chaque étape).
- **Parlez à Claude Code, à voix haute** *(expérimental)*. Un assistant vocal optionnel tient une conversation parlée de type talkie-walkie avec Claude Code — appuyez sur le **bouton latéral** de la télécommande, parlez, appuyez à nouveau, et il vous relit la réponse. En ligne + lecture seule, sur activation, tenu à l'écart du cœur sur l'appareil.
- **Contrôle sans les mains par caméra.** Ouvrez **Caméra** et il suit votre **visage / mains / corps** en temps réel, entièrement **sur l'appareil** (Apple Vision — la vidéo ne quitte jamais votre Mac). Transformez une main en souris — pointez pour déplacer le curseur, **pincez pour cliquer et glisser** — ou **entraînez vos propres gestes** et associez-les à cliquer / défiler / Esc / Espace.
- **Gardez votre Mac éveillé — même capot fermé sur batterie.** Un interrupteur de la barre de menus façon Amphetamine empêche le Mac de se mettre en veille pour que le Wi-Fi / un partage de connexion du téléphone reste actif pendant que vous vous absentez : choisissez **30 min / 1 h / 2 h**, ou laissez-le **actif jusqu'à ce que la batterie atteigne 15 %**, avec un compte à rebours en direct à côté de l'icône de la barre de menus.

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

**Télécommande Apple TV (2ᵉ / 3ᵉ génération)** — appuyez sur **TV** pour parler, appuyez à nouveau sur **TV** pour saisir vos mots au niveau du curseur, **Back ‹ / Esc** pour annuler, faites glisser le **pavé tactile** pour déplacer la souris :

![Démo de la télécommande Apple TV](design/demo-remote.svg)

**Parcours d'installation interactif** — ouvrez [`design/dontype-install-flow.html`](design/dontype-install-flow.html) dans un navigateur pour vivre l'intégralité de la première utilisation (8 écrans : Bienvenue → consentement à la vie privée → autorisations → modèle → raccourci → lecture à voix haute → IA → terminé).

> Les deux démos ci-dessus sont des SVG animés (ils s'animent dans le README). Pour le rendu réel, enregistrez de courts GIF de l'application avec `Cmd+Shift+5` → Gifski / Kap ; une fois le dépôt public, vous pouvez aussi héberger le parcours HTML via GitHub Pages.

## Langues de reconnaissance prises en charge

> **Point essentiel : il n'existe pas de « packs de reconnaissance par langue ».** Un seul modèle whisper couvre environ 99 langues — il suffit de définir la langue ou d'utiliser la détection automatique. Vous ne téléchargez jamais plusieurs modèles, un par langue.

**Détection automatique par défaut** (`recognitionLang: auto`) — il devine ce que vous parlez, aucun choix manuel n'est nécessaire. Le menu déroulant de la langue de reconnaissance ne liste que les langues **mises en avant** pour un verrouillage manuel :

| Niveau | Langues | Remarques |
|------|-----------|-------|
| **Mises en avant** (dans le menu déroulant, officiellement prises en charge) | English · Chinese (Mandarin) · 日本語 · 한국어 · Spanish · French | turbo ≈ large-v3 complet ; sans risque à annoncer |
| Fonctionnent, avec réserves | Cantonese · Thai · Vietnamese, etc. | turbo se dégrade nettement sur le cantonais/thaï → basculez `whisperModel` sur `large-v3` ; absentes du menu déroulant, mais la détection automatique les reconnaît tout de même |
| Faibles (non annoncées) | langues peu dotées | taux d'erreur plus élevé, sujettes aux hallucinations |

- **turbo vs large-v3** : le `large-v3-turbo` par défaut est rapide et ≈ de qualité complète pour les langues bien dotées ; il faiblit sur celles qui le sont peu (notamment le cantonais, le thaï). Basculez `whisperModel` sur `large-v3` pour une meilleure précision multilingue.
- **La langue de l'interface** (menus / assistant) est distincte de la reconnaissance — actuellement le chinois / l'anglais, avec repli sur l'anglais ailleurs. Une interface en japonais / coréen, etc. pourra être ajoutée progressivement lorsqu'un marché justifiera le travail de traduction.

## Installation

**[⬇ Téléchargez la dernière version](https://github.com/easylii/dontype/releases/latest)** — récupérez `Dontype.dmg`, ouvrez-le, faites un clic droit sur **install.command** → « Ouvrir » (étape Gatekeeper unique pour une app auto-signée) ; le script copie vers `/Applications`, retire la quarantaine (le double-clic fonctionne ensuite), écrit une configuration par défaut et lance l'application.

**Ou compilez le DMG vous-même** : `./make-dmg.sh` génère `Dontype.dmg` de la même façon (intégrant `install.command` / `PRIVACY.md` / les notes d'installation).

**Premier lancement = assistant de configuration paginé** : Bienvenue → **Politique de confidentialité (acceptation obligatoire pour continuer)** → Autorisations → Modèle → Raccourci → Lecture à voix haute → IA → Terminé. Ensuite, « Réglages » dans la barre de menus ouvre un **panneau de réglages à fenêtre unique** (et non plus le flux paginé).

**Développement local** :

```bash
cd ~/Documents/SiYu
./build-app.sh          # build + bundle + sign → Dontype.app
open Dontype.app
```

> Remarque : le Finder / les autorisations / les menus affichent la marque **Dontype** (systèmes anglophones) / **丝语** (systèmes chinois), via la localisation `Info.plist` + `Resources/*.lproj`.
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

## Télécommande Apple TV (2ᵉ / 3ᵉ génération)

Pilotez Dontype sans les mains depuis l'autre bout de la pièce avec une **Siri Remote (2ᵉ ou 3ᵉ génération)** — aucun matériel supplémentaire ; elle s'appaire en Bluetooth comme n'importe quel périphérique de saisie du Mac. Activez-la dans la page **⑧ Télécommande** de l'assistant de configuration (avec le parcours animé ci-dessus) ; une autorisation ponctuelle de **Surveillance de la saisie** permet à l'application de lire les touches de la télécommande.

| Télécommande | Ce que ça fait |
|--------|--------------|
| **TV** | Commencer à parler — **appuyez à nouveau** pour terminer et saisir le texte au niveau de votre curseur |
| **Centre (OK)** | **Envoyer** — juste après une dictée, il appuie sur **Entrée** (déclenche votre prompt) ; ailleurs, active le contrôle ciblé / clique au niveau du curseur |
| **Back ‹ / Esc** | Annuler — arrête instantanément la dictée/lecture à voix haute, rien n'est transcrit, rien n'est collé |
| **↑ / ↓** | Déplacement vers le haut et le bas dans les listes, menus et barres latérales |
| **← / →** | Tab / Maj-Tab entre les contrôles (liens, boutons, champs) |
| **Bouton latéral** | Basculer l'**assistant vocal** (parole de type talkie-walkie avec Claude Code) |
| **Pavé tactile** | Faire glisser le curseur de la souris ; cliquer avec le bouton central |

Le volume, la coupure du son et lecture/pause conservent leur fonction système normale. Activer la télécommande active aussi la **navigation au clavier** de macOS (Accès complet au clavier) pour que Tab puisse atteindre les boutons, et pas seulement les champs de texte.

> Les trois canaux d'entrée de la télécommande utilisent chacun une API macOS différente (les touches multimédias via un CGEvent tap, les touches spéciales via IOHIDManager, la surface tactile via le framework privé MultitouchSupport). Ce dernier point signifie que l'application n'est pas isolable pour l'App Store — c'est une fonctionnalité pour utilisateurs avancés que vous activez sur la page Télécommande.

## Suivi par caméra et gestes de la main

Ouvrez **Caméra** depuis le menu pour suivre votre **visage / mains / corps** en temps réel — entièrement **sur l'appareil** via Apple Vision, de sorte que la vidéo ne quitte jamais votre Mac (un aperçu miroir en direct est disponible ; activez visage / mains / corps indépendamment). Deux modes de contrôle sans les mains s'appuient dessus :

- **La main en guise de souris** — pointez avec votre index pour faire glisser le curseur et **pincez** pour cliquer et glisser (mappage absolu et lissé qui couvre tous vos écrans). Un pavé tactile aérien par caméra — sans pavé tactile physique.
- **Entraînez vos propres gestes** — ouvrez l'entraîneur, nommez un geste, choisissez une action (**clic gauche / droit, défilement vers le haut / bas, Esc, Espace**), et maintenez la pose face à la caméra pendant environ 1 seconde (enregistrez-la plusieurs fois pour plus de précision). Il apprend en few-shot sur l'appareil (points de repère de la main d'Apple Vision + plus proche voisin) et déclenche votre action dès qu'il reconnaît le geste.

Tout s'exécute en local ; la caméra s'active depuis le menu et nécessite une autorisation ponctuelle de Caméra.

## Rester éveillé (rester connecté, même capot fermé)

Un interrupteur **Rester éveillé** façon Amphetamine dans la barre de menus empêche le Mac de se mettre en veille — pour que le Wi-Fi ou un partage de connexion du téléphone reste connecté pendant que vous vous absentez ou fermez le capot. Choisissez **30 min / 1 h / 2 h**, ou **Actif jusqu'à batterie ≤ 15 %** ; un **compte à rebours** en direct s'affiche à côté de l'icône de la barre de menus, et vous pouvez le désactiver à tout moment. Il se désactive automatiquement à la fin du minuteur, lorsque la batterie descend à 15 % (sur batterie), ou lorsque vous quittez l'application.

Sur Apple Silicon, rester éveillé **capot fermé sur batterie** est quelque chose que les assertions d'alimentation IOKit et `caffeinate -s` ne peuvent pas faire — c'est imposé par le firmware. Rester éveillé utilise `pmset disablesleep` au niveau root, autorisé **une seule fois** via une règle sudoers à portée étroite (uniquement `pmset disablesleep 0|1`, validée avec `visudo` avant l'installation) ; ensuite, il bascule silencieusement — nécessaire car la désactivation automatique programmée / sur batterie faible peut se produire alors que le capot est fermé, quand aucune invite de mot de passe ne pourrait être vue.

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
| `recognitionLang` | langue de reconnaissance (`auto` / `en` / `zh` / `ja` / `ko` / `es` / `fr`) | `auto` |
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
| `RemoteHID.swift` | touches spéciales de la télécommande Apple TV (IOHIDManager, HID report id=251) → actions |
| `Multitouch.swift` | surface tactile de la télécommande → curseur de la souris (MultitouchSupport privé, family 0x91) |
| `Camera.swift` | caméra + suivi Vision sur l'appareil (visage / mains / corps), aperçu miroir, main en guise de souris (clic par pincement / glisser) |
| `Gestures.swift` | entraîneur de gestes personnalisés (few-shot : points de repère de la main d'Apple Vision + k-NN) → actions (clic / défilement / Esc / Espace) |
| `KeepAwake.swift` | rester éveillé : empêcher la veille, y compris capot fermé sur batterie (`pmset disablesleep`, autorisation sudoers ponctuelle), désactivation automatique programmée / sur batterie, compte à rebours dans la barre de menus |
| `RemoteSetup.swift` | page de configuration / démo de la télécommande (consciente de la connexion, parcours SVG animé) |
| `GameControllerInput.swift` | saisie par manette Bluetooth (dictée / curseur / flèches) |
| `Assistant.swift` · `VoiceLoop.swift` · `VoiceOrb.swift` | assistant vocal : session de flux Claude Code, boucle de tours talkie-walkie, orbe de statut |
| `AudioDevices.swift` | sélection de la source du microphone |
| `L.swift` | localisation de l'interface (zh/en) · `Config.swift` configuration à l'exécution |

`design/dontype-install-flow.html` est le prototype interactif du flux d'installation (pour la démo).

## Feuille de route

- **Reconnaissance en flux continu** : le texte au fur et à mesure que vous parlez (whisper-server est déjà résident ; il peut faire du streaming par segments).
- **Accélération CoreML** : activer CoreML pour l'encodeur whisper.
- **Notarisation Developer ID** : passer à une signature + notarisation pour supprimer le « clic droit → Ouvrir » du premier lancement.
