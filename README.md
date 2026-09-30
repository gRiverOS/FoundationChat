# FoundationChat

App de práctica en SwiftUI para el curso **Getting Started with Apple Foundation Models** (Packt / Coursera). Usa el modelo de lenguaje on-device de Apple Intelligence (~3B parámetros) con el framework `FoundationModels`.

Código oficial del curso (solo secciones 1 y 2, hecho con iOS 26): https://github.com/PacktPublishing/Getting-Started-with-Apple-Foundation-Models

Repaso para el examen final (ficha + 20 preguntas de práctica): https://claude.ai/artifact/DSMSy3KdYXqzwUWUHq7bXM (privado)

## Requisitos

- Mac con Apple Silicon, **macOS 26+** y Apple Intelligence activado
- **Xcode 26+** (probado con Xcode 27)
- iOS 26+ (deployment target `26.0`)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) para generar el proyecto

```bash
xcodegen generate
open FoundationChat.xcodeproj
```

> ⚠️ **Simulador:** el runtime de iOS del simulador debe coincidir con la versión mayor de macOS del host. Con macOS 27, un simulador iOS 26.3 falla con `GenerationError -1` ("Asset … not found in Model Catalog"); uno con iOS 27 funciona. En un iPhone físico compatible funciona directo.

## Pestañas

| Pestaña | Concepto | Archivos |
|---|---|---|
| **Chat** | Sesión, streaming, tool calling, contexto | `ChatViewModel.swift`, `ContentView.swift`, `Tools.swift`, `TranscriptView.swift` |
| **Recetas** | Guided generation con `@Generable` / `@Guide` | `Recipe.swift`, `RecipeView.swift` |
| **Opciones** | `GenerationOptions` (sampling, temperature, tokens) | `OptionsView.swift` |

## Conceptos

### 1. Disponibilidad
Flujo obligatorio: **verificar disponibilidad → crear sesión → enviar prompt.**

`SystemLanguageModel.default.availability` devuelve `.available` o `.unavailable(reason)`: `deviceNotEligible`, `appleIntelligenceNotEnabled`, `modelNotReady`. Incluir siempre un `case .unavailable:` genérico al final, por si Apple agrega razones nuevas.

`AvailabilityGate` (`AvailabilityGate.swift`) envuelve **las tres pestañas**, así que ninguna llama al modelo sin verificar. Muestra un `ContentUnavailableView` distinto por cada razón.

Probar los casos:
- **Xcode:** Edit Scheme → Run → *Simulated Foundation Model Availability* (ojo: `xcodegen generate` regenera el scheme y borra ese ajuste).
- **Terminal (override DEBUG propio):** `SIMCTL_CHILD_FM_SIMULATE=notEligible|notEnabled|notReady xcrun simctl launch <UDID> com.gustavo.FoundationChat`

iOS 27 agrega `PrivateCloudComputeLanguageModel`, con su propia disponibilidad (`deviceNotEligible`, `systemNotReady`).

### 2. Sesión y streaming
```swift
let session = LanguageModelSession(instructions: "...")
for try await snapshot in session.streamResponse(to: prompt) {
    text = snapshot.content   // snapshot ACUMULADO, no delta
}
```
- **Instructions** (reglas del desarrollador) ≠ **prompt** (lo que pide el usuario). El modelo prioriza las instructions sobre el prompt, pero eso **no es una garantía de seguridad**: nunca meter input del usuario en las instructions (prompt injection).
- **Single-turn vs multi-turn:** sesión nueva por pregunta = sin memoria (pestaña Opciones, resumen de contexto); misma sesión reutilizada = recuerda (Chat, sesión como propiedad del view model). Prueba real con `.greedy`:

  | Seguimiento a "¿Dónde viven los pingüinos?" | Single-turn | Multi-turn |
  |---|---|---|
  | "¿Vuelan?" | "No vuelan." (acierta por suerte) | "No vuelan, ya que tienen adaptaciones para nadar…" |
  | "¿Cuál es la especie más grande?" | "El elefante africano." ❌ | "El pingüino emperador." ✅ |

  Para probar memoria, usar un seguimiento donde adivinar no sirva.
- **Prompts específicos:** "Háblame de perros" → párrafo genérico que se corta; "Escribe tres frases que describan la raza Husky Siberiano" → exactamente 3 frases numeradas. Tareas complejas → varios prompts específicos.
- En SwiftUI, llamar al modelo desde `.task` (no `.onAppear`), y **solo cuando está disponible**: si el `.task` va en el contenedor del `switch` de disponibilidad, corre igual cuando el modelo no está. Con `AvailabilityGate` el contenido (y su `.task`) solo existe si está disponible.
- Una sesión atiende **un request a la vez** → revisar `isResponding`.
- Consumir el stream desde un view model `@MainActor` → UI segura sin bloquear.

### 3. Guided generation (`@Generable`)
**Salida tipada:** en vez de un `String` que hay que interpretar (o un JSON que puede salir mal formado), el modelo entrega una instancia de tu struct con tipos de Swift (`Int`, `String`, arreglos, enums). El framework restringe los tokens mientras genera, así que un campo `Int` con `.range(5...180)` no puede recibir "media hora", y un enum solo acepta sus casos. Se usa en `Recipe`, en los `Arguments` de las tools y en `ConversationSummary`.

```swift
@Generable struct Recipe {
    @Guide(description: "Minutos totales", .range(5...180)) var minutes: Int
    @Guide(.count(3...10)) var ingredients: [String]
    var difficulty: Difficulty   // @Generable enum → solo valores válidos
}
session.streamResponse(to: prompt, generating: Recipe.self)  // → Recipe.PartiallyGenerated
```
- El modelo devuelve structs tipados; no hay que parsear JSON.
- En streaming llega `PartiallyGenerated` (propiedades opcionales) que se llena campo a campo.
- Las propiedades se generan **en el orden declarado**. Esto permite un *chain-of-thought* estructurado: un campo de razonamiento o evidencia **antes** del resultado hace que el modelo "piense" primero y ancle la respuesta en el texto fuente:
  ```swift
  @Generable struct Summary {
      @Guide(description: "Hechos clave extraídos del texto") var evidence: [String]  // primero
      var summary: String                                                             // después
  }
  ```
  Costo: más tokens (ventana ~4K) y más latencia.

### 4. Tool calling
```swift
struct PantryTool: Tool {
    let name = "consultarDespensa"
    let description = "..."
    @Generable struct Arguments { var categoria: Categoria }
    func call(arguments: Arguments) async throws -> String { ... }
}
LanguageModelSession(tools: [PantryTool(), DateTimeTool()], instructions: ...)
```
- El modelo decide cuándo llamar según `name`, `description` e instructions.
- **Aprendizaje (evolución de la despensa):**

  | Versión | ¿Preguntó antes? | Categoría |
  |---|---|---|
  | Instructions vagas | Sí, dos veces | la eligió el usuario |
  | Instructions largas y explícitas | No | `abarrotes` ❌ |
  | Instructions cortas + regla en el `@Guide` del argumento | No | `todo` ✅ |

  Un modelo chico sigue mejor una regla **pegada al campo que llena** (`@Guide`) que mezclada en las instructions. Aun así, con sampling aleatorio un acierto no garantiza el siguiente: lo crítico se restringe en código (`Arguments {}` vacío o `.greedy`).
- `call` corre fuera del main actor (Swift 6): actualizar UI con `await`.

### 5. GenerationOptions
```swift
GenerationOptions(
    samplingMode: .greedy,                // determinista (iOS 26: `sampling:`, deprecado en iOS 27)
           // .random(top: 40)            // top-k
           // .random(probabilityThreshold: 0.9)  // top-p
    temperature: 0.7,
    maximumResponseTokens: 60             // corta a mitad de frase
)
session.respond(to: prompt, options: options)
```
| Uso | Configuración |
|---|---|
| Extracción, clasificación, tests | `.greedy` |
| Chat consistente | temperature 0.3–0.7 |
| Ideas, nombres, brainstorming | temperature 1.2+ |

Resultado real: greedy → 3 respuestas idénticas; top-k 40 + temp 2.0 → 3 distintas.

**Config por request, no global:** `GenerationOptions` se pasa en cada `respond(to:options:)`. Un ajuste global (p. ej. temperature 0.9 para todo) contamina tareas que necesitan precisión, como extraer datos, y es frágil con requests concurrentes.

**Receta para resumir documentos:** temperature baja o `.greedy`; el largo se pide en el prompt ("en 3 viñetas") y `maximumResponseTokens` es solo un tope de seguridad; en las instructions, "usa solo información del texto"; documentos largos → dividir en partes, resumir cada una y luego resumir los resúmenes.

**Rango de temperature:** en la beta de iOS 26 (la del curso) había que usar valores entre 0 y 1, y 1.2 daba error. En iOS/macOS 27 funcionan 1.2 y 2.0 sin error (probado). iOS 27 además agrega `toolCallingMode` en `GenerationOptions`.

**¿Es determinista?** El modelo sí: con la misma entrada calcula siempre la misma distribución de probabilidades. Lo aleatorio es el **sampling**, y el default de `LanguageModelSession` es aleatorio. Con `.greedy` la generación es determinista **ante exactamente la misma entrada** (mismas instructions, prompt e historial). Límites: una actualización del modelo con iOS puede cambiar las respuestas (no hacer tests que comparen texto exacto), y `.random(top:seed:)` da variedad reproducible sin garantía entre dispositivos o versiones.

### 6. Sesiones y contexto
- `session.transcript` = memoria de la sesión (instructions, prompts, responses, tool calls/outputs). **Todo consume la ventana de contexto (~4K tokens).**
- `session.prewarm()` al aparecer la pantalla → menos latencia en la 1.ª respuesta.
- Al recibir `exceededContextWindowSize`: resumir la conversación con otra sesión, crear una sesión nueva con el resumen en sus instructions y reintentar el prompt (`condenseContext()`).
- El resumen usa `@Generable struct ConversationSummary { userFacts: [String]; topic: String }` con `.greedy`. Con texto libre ("resume en 3 frases") el modelo casi copió la última respuesta; con el struct extrajo `[Gustavo; vegetariano]` y tema "Recetas vegetarianas", y la sesión nueva respondió "Hola, Gustavo. Eres vegetariano." Extraer campos concretos es más confiable que pedir prosa a un modelo chico.
- Mejora posible: conservar las últimas 2–3 interacciones tal cual además del resumen.

### 7. Guardrails y errores
Todos los errores pasan por `ModelErrors.message(for:)` (`ModelErrors.swift`), que los traduce a mensajes claros.

⚠️ **iOS 27 cambió el tipo de error.** iOS 26 lanza `LanguageModelSession.GenerationError`; iOS 27 lanza el nuevo `LanguageModelError` (`guardrailViolation`, `refusal`, `contextSizeExceeded`, `rateLimited`, `timeout`, `unsupportedLanguageOrLocale`, …). Hay que manejar ambos con `#available(iOS 27, *)`. Un `catch GenerationError.exceededContextWindowSize` **no atrapa** el overflow en iOS 27 → usar `ModelErrors.isContextOverflow(_:)`.

- **Guardrail** (`guardrailViolation`): los filtros de seguridad de Apple bloquean el prompt o la respuesta. La sesión sigue usable después.
- **Refusal**: el modelo decide no responder (distinto del guardrail).
- Errores lanzados dentro de una tool llegan envueltos en `LanguageModelSession.ToolCallError`.
- Crear la sesión no lanza; lanzan `respond` / `streamResponse`.

### 8. Rendimiento con Instruments
Plantilla **Foundation Models** (Xcode 26+). En la app: Xcode → Open Developer Tool → Instruments → Blank → agregar el instrument *Foundation Models*. Por línea de comandos:
```bash
xcrun xctrace record --template "Foundation Models" --device <UDID> \
  --attach FoundationChat --time-limit 45s --output traces/fm.trace   # pide Enter: guarda prompts sin cifrar
xcrun xctrace export --input traces/fm.trace --toc                     # tablas: RequestTable, ModelInferenceTable, ToolTable…
```
`traces/` está en `.gitignore` porque los traces guardan prompts y respuestas en texto plano.

Mediciones reales (simulador iOS 27, una muestra):

| | Antes | Instructions cortas | Cambio |
|---|---|---|---|
| Sin tool: tokens de entrada | 340 | 209 | −39% |
| Sin tool: duración | 1,64 s | 2,21 s | ruido (modelo frío tras relanzar) |
| Con tool: tokens totales | 895 | 560 | −37% |
| Con tool: duración | 3,27 s | 2,02 s | −38% |

Lecciones:
- Instructions + definiciones de tools se envían en **cada** request (~300 tokens fijos antes de optimizar).
- Procesar el prompt tarda más que generar (1,20 s vs 0,44 s): achicar instructions y descriptions rinde más.
- **Una tool = dos inferencias**: decidir la llamada + responder con el output en contexto → casi duplica la latencia.
- `cached-tokens = 0`: el contexto no se reusó entre requests.
- En el simulador la `ToolTable` sale vacía aunque la tool se llame.
- Para conclusiones serias: ~5 repeticiones por caso, idealmente en dispositivo físico.

## Pendiente
- [ ] Despensa 100% repetible: `Arguments {}` vacío o `.greedy` (hoy acierta con la regla en el `@Guide`, pero el sampling es aleatorio)
- [ ] Probar chain-of-thought estructurado (`evidence` antes de `summary`) y medir su costo en tokens
- [ ] Adapters
