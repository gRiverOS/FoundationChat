# FoundationChat

App de práctica en SwiftUI para el curso **Getting Started with Apple Foundation Models** (Packt / Coursera). Usa el modelo de lenguaje on-device de Apple Intelligence (~3B parámetros) con el framework `FoundationModels`.

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
`SystemLanguageModel.default.availability` devuelve `.available` o `.unavailable(reason)` (`deviceNotEligible`, `appleIntelligenceNotEnabled`, `modelNotReady`). Siempre verificarlo y mostrar un fallback.

### 2. Sesión y streaming
```swift
let session = LanguageModelSession(instructions: "...")
for try await snapshot in session.streamResponse(to: prompt) {
    text = snapshot.content   // snapshot ACUMULADO, no delta
}
```
- **Instructions** (reglas del desarrollador) ≠ **prompt** (lo que pide el usuario).
- Una sesión atiende **un request a la vez** → revisar `isResponding`.
- Consumir el stream desde un view model `@MainActor` → UI segura sin bloquear.

### 3. Guided generation (`@Generable`)
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
- Las propiedades se generan **en el orden declarado**.

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
- **Aprendizaje:** el modelo on-device es conservador; con instrucciones vagas pregunta en vez de llamar la tool. Con instrucciones directas llama al tiro, pero **igual puede elegir mal un argumento** (pidió `abarrotes` en vez de `todo`). Lo crítico se restringe en código, no en el prompt.
- `call` corre fuera del main actor (Swift 6): actualizar UI con `await`.

### 5. GenerationOptions
```swift
GenerationOptions(
    sampling: .greedy,                    // determinista
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

### 6. Sesiones y contexto
- `session.transcript` = memoria de la sesión (instructions, prompts, responses, tool calls/outputs). **Todo consume la ventana de contexto (~4K tokens).**
- `session.prewarm()` al aparecer la pantalla → menos latencia en la 1.ª respuesta.
- Al recibir `exceededContextWindowSize`: resumir la conversación con otra sesión, crear una sesión nueva con el resumen en sus instructions y reintentar el prompt (`condenseContext()`).
- Mejora pendiente: resumir con `@Generable` (`userFacts`, `topic`) y conservar las últimas 2–3 interacciones tal cual.

### 7. Guardrails y errores
Todos los errores pasan por `ModelErrors.message(for:)` (`ModelErrors.swift`), que los traduce a mensajes claros.

⚠️ **iOS 27 cambió el tipo de error.** iOS 26 lanza `LanguageModelSession.GenerationError`; iOS 27 lanza el nuevo `LanguageModelError` (`guardrailViolation`, `refusal`, `contextSizeExceeded`, `rateLimited`, `timeout`, `unsupportedLanguageOrLocale`, …). Hay que manejar ambos con `#available(iOS 27, *)`. Un `catch GenerationError.exceededContextWindowSize` **no atrapa** el overflow en iOS 27 → usar `ModelErrors.isContextOverflow(_:)`.

- **Guardrail** (`guardrailViolation`): los filtros de seguridad de Apple bloquean el prompt o la respuesta. La sesión sigue usable después.
- **Refusal**: el modelo decide no responder (distinto del guardrail).
- Errores lanzados dentro de una tool llegan envueltos en `LanguageModelSession.ToolCallError`.
- Crear la sesión no lanza; lanzan `respond` / `streamResponse`.

## Pendiente
- [ ] Despensa confiable: `Arguments {}` vacío en vez de depender del argumento
- [ ] Resumen de contexto con `@Generable`
- [ ] Medir rendimiento con Instruments (plantilla Foundation Models)
- [ ] Adapters
