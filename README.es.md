# Dontype (丝语)

[English](README.md) · [中文](README.zh.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · **Español** · [Français](README.fr.md)

**El compañero de voz definitivo para el vibe coding en Mac**, por **Easylii**. Marca occidental **Dontype** (don't type — solo habla), marca china **丝语**.

El vibe coding consiste en *hablar* con tu IA, no en teclearlo todo. Dontype hace que tu Mac escuche: dicta prompts directamente en **Claude Code, Cursor o cualquier campo** — pulsa dos veces **Control**, habla, y transcribe en local, elimina las muletillas y pega en tu cursor; un botón lo **envía**. Ejecuta todo el bucle **con las manos libres desde un mando de Apple TV**, y haz que las respuestas se te **lean en voz alta**. Todo se ejecuta en el dispositivo; tu voz nunca sale de tu Mac.

## Lo más destacado

- **Hecho para el vibe coding.** Habla tus prompts directamente en Claude Code, Cursor, ChatGPT o cualquier campo de texto — dicta, elimina los "eh" y corrige la gramática, pega en el cursor, y un botón lo **envía** (Return). Recuéstate y ejecuta todo el bucle desde un mando de Apple TV.
- **3 en 1.** Voz → texto (dictado), texto → voz (lee en voz alta cualquier texto seleccionado) y un historial de portapapeles de 5 ranuras: tres herramientas en una sola app diminuta de la barra de menús. La mayoría de las herramientas de dictado solo hacen una.
- **Sin API con medición, sin suscripción adicional.** El reconocimiento se ejecuta totalmente **en local** (gratis, sin conexión, sin ancho de banda). La limpieza con IA se apoya en el **Claude Code / Codex que ya tienes**, a través de su CLI: sin una clave aparte de la Anthropic API y sin facturación de API por token. No hay nada extra que pagar; sin ninguno de los dos, simplemente entrega la transcripción en bruto (igualmente gratis).
- **Historial de portapapeles de 5 ranuras.** Cada resultado de dictado y cada copia manual entra en un historial de 5 elementos (sin duplicados, etiquetado por origen): haz clic en cualquiera para volver a copiarlo. Solo en memoria, se omiten los recortes sensibles.
- **Funciona con el mando de Apple TV (2.ª o 3.ª gen).** Dicta con las manos libres desde el otro lado de la habitación con un Siri Remote: pulsa **TV** para empezar a hablar, **TV** otra vez para terminar, **OK** para enviar, **Back ‹ / Esc** para cancelar, desliza por el **touchpad** para mover el cursor, y las **flechas** actúan como Tab entre controles. Configúralo en la página Mando del asistente de configuración (una demostración animada muestra cada paso).
- **Habla con Claude Code, en voz alta** *(experimental)*. Un asistente de voz opcional mantiene una conversación hablada estilo walkie-talkie con Claude Code — pulsa el **botón lateral** del mando, habla, pulsa de nuevo, y lee la respuesta en voz alta. En línea + solo lectura, opcional, mantenido separado del núcleo que se ejecuta en el dispositivo.
- **Control con las manos libres mediante la cámara.** Abre **Cámara** y rastrea tu **cara / manos / cuerpo** en tiempo real, totalmente **en el dispositivo** (Apple Vision — el vídeo nunca sale de tu Mac). Convierte una mano en un ratón — apunta para mover el cursor, **pellizca para hacer clic y arrastrar** — o **entrena tus propios gestos** y asígnalos a clic / desplazamiento / Esc / Espacio.
- **Mantén tu Mac despierto — incluso con la tapa cerrada y con batería.** Un interruptor de la barra de menús estilo Amphetamine impide que el Mac entre en reposo para que el Wi-Fi o el punto de acceso del móvil sigan activos mientras te alejas: elige **30 min / 1 h / 2 h**, o déjalo **activado hasta que la batería llegue al 15 %**, con una cuenta atrás en vivo junto al icono de la barra de menús.

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

**Mando de Apple TV (2.ª / 3.ª gen)** — pulsa **TV** para hablar, pulsa **TV** otra vez para escribir tus palabras en el cursor, **Back ‹ / Esc** para cancelar, desliza por el **touchpad** para mover el ratón:

![Demostración del mando de Apple TV](design/demo-remote.svg)

**Recorrido interactivo de instalación** — abre [`design/dontype-install-flow.html`](design/dontype-install-flow.html) en un navegador para la experiencia completa de primer arranque (8 pantallas: Bienvenida → consentimiento de privacidad → permisos → modelo → atajo → lectura en voz alta → IA → listo).

> Las dos demostraciones anteriores son SVG animados (se reproducen en el README). Para lo real, graba GIF cortos de la app con `Cmd+Shift+5` → Gifski / Kap; una vez que el repositorio sea público también puedes alojar el recorrido HTML mediante GitHub Pages.

## Idiomas de reconocimiento admitidos

> **Punto clave: no hay "paquetes de reconocimiento por idioma".** Un solo modelo de whisper cubre ~99 idiomas: basta con fijar el idioma o usar la detección automática. Nunca descargas varios modelos por idioma.

**Detección automática por defecto** (`recognitionLang: auto`) — descubre qué estás hablando, sin necesidad de elegir manualmente. El menú desplegable de idioma de reconocimiento solo lista los idiomas **destacados** para bloquearlos manualmente:

| Nivel | Idiomas | Notas |
|------|-----------|-------|
| **Destacados** (en el desplegable, con soporte oficial) | English · Chinese (Mandarin) · 日本語 · 한국어 · Spanish · French | turbo ≈ large-v3 completo; seguro para promocionar |
| Funciona, con salvedades | Cantonese · Thai · Vietnamese, etc. | turbo se degrada notablemente en cantonés/tailandés → cambia `whisperModel` a `large-v3`; no está en el desplegable, pero la detección automática igualmente los reconoce |
| Débil (no se promociona) | idiomas de pocos recursos | mayor tasa de error, propensos a alucinaciones |

- **turbo frente a large-v3**: el `large-v3-turbo` por defecto es rápido y ≈ calidad completa para idiomas de muchos recursos; cae en los de pocos recursos (en particular cantonés y tailandés). Cambia `whisperModel` a `large-v3` para una mejor precisión multilingüe.
- **El idioma de la interfaz** (menús / asistente) es independiente del reconocimiento: actualmente chino / inglés, con respaldo a inglés en los demás casos. La interfaz en japonés / coreano, etc., puede añadirse de forma gradual cuando un mercado justifique el trabajo de traducción.

## Instalación

**[⬇ Descarga la última versión](https://github.com/easylii/dontype/releases/latest)** — consigue `Dontype.dmg`, ábrelo, haz clic derecho en **install.command** → "Abrir" (paso único de Gatekeeper por ser una app autofirmada); el script copia a `/Applications`, elimina la cuarentena (después funciona con doble clic), escribe una configuración por defecto y se inicia.

**O compila el DMG tú mismo**: `./make-dmg.sh` genera `Dontype.dmg` de la misma manera (incluye `install.command` / `PRIVACY.md` / notas de instalación).

**Primer arranque = asistente de configuración paginado**: Bienvenida → **Política de privacidad (hay que aceptar para continuar)** → Permisos → Modelo → Atajo → Lectura en voz alta → IA → Listo. Después, "Ajustes" en la barra de menús abre un **panel de ajustes de una sola ventana** (ya no el flujo paginado).

**Desarrollo local**:

```bash
cd ~/Documents/SiYu
./build-app.sh          # build + bundle + sign → Dontype.app
open Dontype.app
```

> Nota: Finder / permisos / menús muestran la marca **Dontype** (sistemas en inglés) / **丝语** (sistemas en chino), mediante la localización de `Info.plist` + `Resources/*.lproj`.
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

## Mando de Apple TV (2.ª / 3.ª gen)

Controla Dontype con las manos libres desde el otro lado de la habitación con un **Siri Remote (2.ª o 3.ª generación)** — sin hardware adicional; se empareja por Bluetooth como cualquier dispositivo de entrada del Mac. Actívalo en la página **⑧ Mando** del asistente de configuración (con el recorrido animado de arriba); un permiso único de **Monitorización de entrada** permite a la app leer las teclas del mando.

| Mando | Qué hace |
|--------|--------------|
| **TV** | Empieza a hablar — **pulsa de nuevo** para terminar y escribir el texto en tu cursor |
| **Centro (OK)** | **Enviar** — justo después de un dictado pulsa **Return** (dispara tu prompt); en otro contexto activa el control enfocado / hace clic en el cursor |
| **Back ‹ / Esc** | Cancelar — detiene el dictado/lectura en voz alta al instante, nada se transcribe, nada se pega |
| **↑ / ↓** | Sube y baja por listas, menús y barras laterales |
| **← / →** | Tab / Shift-Tab entre controles (enlaces, botones, campos) |
| **Botón lateral** | Alterna el **asistente de voz** (habla estilo walkie-talkie con Claude Code) |
| **Touchpad** | Desliza el cursor del ratón; haz clic con el botón central |

El volumen, el silencio y reproducir/pausar mantienen su función normal del sistema. Activar el mando también enciende la **navegación por teclado** de macOS (Full Keyboard Access) para que Tab pueda alcanzar los botones, no solo los campos de texto.

> Los tres canales de entrada del mando usan cada uno una API distinta de macOS (las teclas multimedia mediante un CGEvent tap, las teclas especiales mediante IOHIDManager, la superficie táctil mediante el framework privado MultitouchSupport). Este último implica que la app no puede aislarse en el sandbox de la App Store — es una función para usuarios avanzados que activas en la página Mando.

## Seguimiento por cámara y gestos de la mano

Abre **Cámara** desde el menú para rastrear tu **cara / manos / cuerpo** en tiempo real — totalmente **en el dispositivo** mediante Apple Vision, de modo que el vídeo nunca sale de tu Mac (hay una vista previa reflejada en vivo; activa cara / manos / cuerpo de forma independiente). Se apoyan en él dos modos de control con las manos libres:

- **La mano como ratón** — apunta con el dedo índice para deslizar el cursor y **pellizca** para hacer clic y arrastrar (mapeo absoluto y suavizado que abarca todas tus pantallas). Un trackpad aéreo por cámara — sin necesidad de touchpad.
- **Entrena tus propios gestos** — abre el entrenador, ponle nombre a un gesto, elige una acción (**clic izquierdo / derecho, desplazar arriba / abajo, Esc, Espacio**) y mantén la pose frente a la cámara durante ~1 segundo (grábalo unas cuantas veces para mayor precisión). Aprende con pocos ejemplos en el dispositivo (puntos de referencia de la mano de Vision + vecino más cercano) y dispara tu acción cada vez que reconoce el gesto.

Todo se ejecuta en local; la cámara es opcional desde el menú y requiere un permiso de Cámara único.

## Mantener despierto (sigue conectado, incluso con la tapa cerrada)

Un interruptor **Mantener despierto** estilo Amphetamine en la barra de menús impide que el Mac entre en reposo — para que el Wi-Fi o el punto de acceso del móvil sigan conectados mientras te alejas o cierras la tapa. Elige **30 min / 1 h / 2 h**, o **Activado hasta que la batería ≤ 15 %**; una **cuenta atrás** en vivo se muestra junto al icono de la barra de menús, y puedes desactivarlo en cualquier momento. Se desactiva automáticamente cuando termina el temporizador, cuando la batería baja al 15 % (con batería), o cuando cierras la app.

En Apple Silicon, mantenerse despierto con la **tapa cerrada y con batería** es algo que las aserciones de energía de IOKit y `caffeinate -s` no pueden hacer — está impuesto por el firmware. Mantener despierto usa `pmset disablesleep` a nivel de root, autorizado **una sola vez** mediante una regla de sudoers de alcance reducido (solo `pmset disablesleep 0|1`, validada con `visudo` antes de la instalación); después de eso se alterna de forma silenciosa — necesario porque la desactivación automática por temporizador / batería baja puede dispararse con la tapa cerrada, cuando no podría verse ningún aviso de contraseña.

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
| `recognitionLang` | idioma de reconocimiento (`auto` / `en` / `zh` / `ja` / `ko` / `es` / `fr`) | `auto` |
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
| `RemoteHID.swift` | teclas especiales del mando de Apple TV (IOHIDManager, HID report id=251) → acciones |
| `Multitouch.swift` | superficie táctil del mando → cursor del ratón (MultitouchSupport privado, familia 0x91) |
| `Camera.swift` | cámara + seguimiento con Vision en el dispositivo (cara / manos / cuerpo), vista previa reflejada, mano como ratón (clic con pellizco / arrastrar) |
| `Gestures.swift` | entrenador de gestos personalizados (pocos ejemplos: puntos de referencia de la mano de Vision + k-NN) → acciones (clic / desplazar / Esc / Espacio) |
| `KeepAwake.swift` | mantener despierto: impide el reposo incl. con la tapa cerrada y con batería (`pmset disablesleep`, autorización de sudoers única), desactivación automática por temporizador / batería, cuenta atrás en la barra de menús |
| `RemoteSetup.swift` | página de configuración / demostración del mando (consciente de la conexión, recorrido en SVG animado) |
| `GameControllerInput.swift` | entrada de gamepad Bluetooth (dictado / cursor / flechas) |
| `Assistant.swift` · `VoiceLoop.swift` · `VoiceOrb.swift` | asistente de voz: sesión de stream de Claude Code, bucle de turnos walkie-talkie, orbe de estado |
| `AudioDevices.swift` | selección del origen del micrófono |
| `L.swift` | localización de la interfaz (zh/en) · `Config.swift` configuración en tiempo de ejecución |

`design/dontype-install-flow.html` es el prototipo interactivo del flujo de instalación (para demostración).

## Hoja de ruta

- **Reconocimiento por streaming**: texto a medida que hablas (whisper-server ya es residente; puede hacer streaming por fragmentos).
- **Aceleración con CoreML**: habilitar CoreML para el codificador de whisper.
- **Notarización con Developer ID**: cambiar la firma + notarizar para eliminar el "clic derecho → Abrir" del primer arranque.
