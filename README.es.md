# Dontype (丝语)

[English](README.md) · [中文](README.zh.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · **Español** · [Français](README.fr.md)

Dictado de voz + lectura en voz alta con prioridad a la privacidad para Mac, por **Easylii**.
Marca occidental **Dontype** (don't type — solo habla), marca china **丝语**. Pulsa dos veces **Control** para empezar a hablar, pulsa una vez para detener: transcripción local, limpieza con IA y pegado automático en el cursor. Todo se ejecuta en el dispositivo; tu voz nunca sale de tu Mac.

## Lo más destacado

- **3 en 1.** Voz → texto (dictado), texto → voz (lee en voz alta el texto seleccionado) y un historial de portapapeles de 5 ranuras: tres herramientas en una sola app de la barra de menús. La mayoría de las herramientas de dictado solo hacen una.
- **Sin API con medición, sin suscripción adicional.** El reconocimiento se ejecuta totalmente **en local** (gratis, sin conexión, sin ancho de banda). La limpieza con IA se apoya en el **Claude Code / Codex que ya tienes**, a través de su CLI: sin una clave aparte de la Anthropic API y sin facturación de API por token. No hay nada extra que pagar; sin ninguno de los dos, simplemente entrega la transcripción en bruto (igualmente gratis).
- **Historial de portapapeles de 5 ranuras.** Cada resultado de dictado y cada copia manual entra en un historial de 5 elementos (sin duplicados, etiquetado por origen): haz clic en cualquiera para volver a copiarlo. Solo en memoria, se omiten los recortes sensibles.

## Cómo funciona

```
Double-tap Control to record (tap to stop / Esc = stop without paste)
  → whisper.cpp local recognition (offline; falls back to Apple speech if no model)
  → AI cleanup (Claude API / Claude Code / Codex, auto-fallback; rewrites into fluent sentences)
  → floating result window + copy button
  → auto-paste into the field you were in
```

## Demostración

**Voz → texto** — pulsa dos veces Control, habla, y el texto se pega en tu cursor:

![Demostración de voz a texto](design/demo-stt.svg)

**Texto → voz** — selecciona texto, pulsa dos veces el ⌘ derecho, y una voz lo lee en voz alta:

![Demostración de texto a voz](design/demo-tts.svg)

**Historial del portapapeles** — tus últimos 5 recortes (dictados + copias manuales), haz clic en uno para volver a copiarlo:

![Demostración del historial del portapapeles](design/demo-clipboard.svg)

**Recorrido interactivo de instalación** — abre [`design/dontype-install-flow.html`](design/dontype-install-flow.html) en un navegador para la experiencia completa de primer arranque (8 pantallas: Bienvenida → consentimiento de privacidad → permisos → modelo → atajo → lectura en voz alta → IA → listo).

> Las dos demostraciones anteriores son SVG animados (se reproducen en el README). Para lo real, graba GIF cortos de la app con `Cmd+Shift+5` → Gifski / Kap; una vez que el repositorio sea público también puedes alojar el recorrido HTML mediante GitHub Pages.

## Idiomas de reconocimiento admitidos

> **Punto clave: no hay "paquetes de reconocimiento por idioma".** Un solo modelo de whisper cubre ~99 idiomas: basta con fijar el idioma o usar la detección automática. Nunca descargas varios modelos por idioma.

**Detección automática por defecto** (`recognitionLang: auto`) — descubre qué estás hablando, sin necesidad de elegir manualmente. El menú desplegable de idioma de reconocimiento solo lista los idiomas **destacados** para bloquearlos manualmente:

| Nivel | Idiomas | Notas |
|------|-----------|-------|
| **Destacados** (en el desplegable, con soporte oficial) | English · Chinese (Mandarin) · 日本語 · 한국어 · Spanish · French · German · Italian · Portuguese | turbo ≈ large-v3 completo; seguro para promocionar |
| Funciona, con salvedades | Cantonese · Thai · Vietnamese, etc. | turbo se degrada notablemente en cantonés/tailandés → cambia `whisperModel` a `large-v3`; no está en el desplegable, pero la detección automática igualmente los reconoce |
| Débil (no se promociona) | idiomas de pocos recursos | mayor tasa de error, propensos a alucinaciones |

- **turbo frente a large-v3**: el `large-v3-turbo` por defecto es rápido y ≈ calidad completa para idiomas de muchos recursos; cae en los de pocos recursos (en particular cantonés y tailandés). Cambia `whisperModel` a `large-v3` para una mejor precisión multilingüe.
- **El idioma de la interfaz** (menús / asistente) es independiente del reconocimiento: actualmente chino / inglés, con respaldo a inglés en los demás casos. La interfaz en japonés / coreano, etc., puede añadirse de forma gradual cuando un mercado justifique el trabajo de traducción.

## Instalación

**Instalación distribuida (recomendada)**: `./make-dmg.sh` genera `Dontype.dmg` (que incluye `install.command` / `PRIVACY.md` / notas de instalación). Para instalar, haz clic derecho en **install.command** dentro del DMG → "Abrir"; el script copia a `/Applications`, elimina la cuarentena (después funciona con doble clic), escribe una configuración por defecto y se inicia.

**Primer arranque = asistente de configuración paginado**: Bienvenida → **Política de privacidad (hay que aceptar para continuar)** → Permisos → Modelo → Atajo → Lectura en voz alta → IA → Listo. Después, "Ajustes" en la barra de menús abre un **panel de ajustes de una sola ventana** (ya no el flujo paginado).

**Desarrollo local**:

```bash
cd ~/Documents/SiYu
./build-app.sh          # build + bundle + sign → SiYu.app
open SiYu.app
```

> Nota: el paquete de la app sigue llamándose `SiYu.app` internamente, pero Finder / permisos / menús muestran la marca **Dontype** (sistemas en inglés) / **丝语** (sistemas en chino), mediante la localización de `Info.plist` + `Resources/*.lproj`.
> El certificado de firma reside en `.cert/` (**no está en el repositorio** — haz una copia de seguridad por separado). Un certificado fijo mantiene válidas la Accesibilidad y otras concesiones de TCC entre recompilaciones.

Tras el arranque aparece un **logo de burbuja** en la barra de menús; se vuelve rojo sólido mientras graba y naranja sólido mientras limpia.

## Historial del portapapeles (hasta 5)

La sección "Entrada de voz" de la barra de menús tiene un **historial del portapapeles** — hasta 5 entradas, haz clic para volver a copiar al portapapeles:
- Dos orígenes, marcados con un icono: 🌊 transcripciones de esta app / 📋 cosas que copiaste manualmente.
- **Deduplicación automática**: el contenido idéntico se conserva una sola vez y se mueve arriba.
- **Solo en memoria, nunca se escribe en disco, se borra al salir**; los elementos del portapapeles marcados como sensibles por los gestores de contraseñas se **omiten**.

## Leer en voz alta el texto seleccionado (sentido inverso)

En **cualquier app**, selecciona texto (o coloca el cursor al inicio) → **pulsa dos veces el ⌘ derecho** → una voz Premium lee **desde ahí hasta el final del bloque de texto actual** (sin conexión, gratis). Mientras lee: **pulsa el ⌘ derecho** para pausar/reanudar, **Esc** para detener.
- Lectura hacia abajo: primero intenta usar Accesibilidad para obtener "el texto completo del campo enfocado + la posición de la selección", leyendo desde el inicio de la selección hasta el final de ese bloque de texto; si no puede (algunas páginas web / terminales / Electron) recurre a **leer solo el fragmento seleccionado**.
- Respaldo de selección: cuando Accesibilidad no puede obtener la selección, sintetiza Cmd+C, lee el portapapeles y lo **restaura**.
- Ajustes: configura la voz / velocidad / tecla de activación / vista previa en el panel de ajustes "⑧ Leer la selección en voz alta → Configurar"; si no tienes ninguna voz Premium, hay un punto de acceso para descargar una en Ajustes del Sistema.

## Privacidad

Tu voz nunca sale del dispositivo — cero recopilación, cero seguimiento, sin cuentas, sin telemetría. La limpieza opcional con IA envía únicamente **texto** (no audio) a la cuenta de Claude/Codex que **tú mismo configuras**. La política completa está en [`PRIVACY.md`](PRIVACY.md) (bilingüe, de nivel GDPR / CCPA). El primer arranque incluye una barrera de consentimiento de privacidad.

## Configuración

El backend de limpieza con IA se selecciona automáticamente por prioridad: `Claude API (fastest) → Claude Code → Codex → raw passthrough`, con respaldo automático en caso de fallo. Para la API más rápida: define `ANTHROPIC_API_KEY`, o coloca `apiKey` en `~/.config/siyu/config.json`. También funciona sin clave: con Claude Code / Codex usa tu suscripción; sin ninguno, entrega la transcripción en bruto.

Campos de `~/.config/siyu/config.json`:

| Campo | Significado | Por defecto |
|-------|---------|---------|
| `apiKey` | clave de la Anthropic API | vacío (recurre a la variable de entorno) |
| `model` | modelo para la limpieza por API | `claude-haiku-4-5-20251001` |
| `cleanup` | activa la limpieza con IA (se dispara automáticamente solo cuando se detectan muletillas) | `true` |
| `autoPaste` | pega automáticamente en el cursor tras un resultado | `true` |
| `whisperModel` | id del modelo de whisper (`large-v3-turbo` / `large-v3` / `medium` / `small`) | `large-v3-turbo` |
| `recognitionLang` | idioma de reconocimiento (`auto` / `en` / `zh` / `ja` / `ko` / `es` / `fr` / `de` / `it` / `pt`) | `auto` |
| `uiLang` | idioma de la interfaz (`auto` / `zh` / `en`) | `auto` |
| `readKey` | tecla de activación de la lectura en voz alta (`control`/`fn`/`rightCommand`/`rightOption`/`option`) | `rightCommand` |
| `readVoice` | id de voz para la lectura en voz alta (vacío = elección automática de Premium según el idioma del texto) | vacío |
| `readRate` | velocidad de la lectura en voz alta 0…1 | `0.5` |

## Estructura

| Archivo | Responsabilidad |
|------|----------------|
| `AppDelegate.swift` | barra de menús, orquestación del flujo, historial del portapapeles, permisos |
| `HotkeyMonitor.swift` | detección global de doble pulsación de teclas modificadoras (CGEventTap) |
| `Dictation.swift` | grabación + reconocimiento (whisper primero, Apple como respaldo) |
| `Whisper.swift` | backend de whisper.cpp: directorio del modelo, idioma de reconocimiento, servidor residente |
| `Cleaner.swift` | limpieza con IA (cadena de respaldo API / Claude Code / Codex; reescribe en frases) |
| `ModelDownloader.swift` | descarga del modelo de whisper (devoluciones de progreso al asistente) |
| `TextGrabber.swift` | captura del texto seleccionado (Accesibilidad directa + respaldo con Cmd+C que restaura el portapapeles) |
| `Speaker.swift` | motor de lectura en voz alta (AVSpeechSynthesizer + voces Premium, elección automática por idioma) |
| `HotkeySetup.swift` / `ReadSetup.swift` | atajo de inicio/parada, configuración de la lectura en voz alta (prueba de doble pulsación para confirmar) |
| `Onboarding.swift` | **asistente paginado** de primer arranque (con consentimiento de privacidad) + **panel de ajustes** del menú (dos modos, una clase) |
| `RecallStore.swift` | historial del portapapeles (hasta 5, deduplicación, en memoria, omite recortes sensibles) |
| `IconRenderer.swift` | icono de la barra de menús + iconos de origen del micrófono (rutas SVG dibujadas en tiempo de ejecución) |
| `HUD.swift` | ventana flotante de resultados / píldora arrastrable / forma de onda de la lectura en voz alta |
| `Paster.swift` | portapapeles + Cmd+V sintético |
| `L.swift` | localización de la interfaz (zh/en) · `Config.swift` configuración en tiempo de ejecución |

`design/dontype-install-flow.html` es el prototipo interactivo del flujo de instalación (para demostración).

## Hoja de ruta

- **Reconocimiento por streaming**: texto a medida que hablas (whisper-server ya es residente; puede hacer streaming por fragmentos).
- **Aceleración con CoreML**: habilitar CoreML para el codificador de whisper.
- **Notarización con Developer ID**: cambiar la firma + notarizar para eliminar el "clic derecho → Abrir" del primer arranque.
