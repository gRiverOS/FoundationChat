# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Qué es

App SwiftUI de práctica para el curso "Getting Started with Apple Foundation Models". Usa el modelo on-device de Apple Intelligence vía el framework `FoundationModels`. Sin dependencias externas, sin tests. El README tiene la explicación de cada concepto del curso.

## Comandos

El `.xcodeproj` se genera con XcodeGen desde `project.yml`: **no editar el `.xcodeproj` a mano**. Después de agregar o borrar archivos `.swift`, regenerar.

```bash
xcodegen generate

# Build para el simulador iOS 27 (el único que funciona con este Mac, ver abajo)
xcodebuild -project FoundationChat.xcodeproj -scheme FoundationChat \
  -destination 'id=409925DC-4CAC-4370-A567-28B1DF07717E' -derivedDataPath build-sim build

# Instalar y lanzar
xcrun simctl install 409925DC-4CAC-4370-A567-28B1DF07717E build-sim/Build/Products/Debug-iphonesimulator/FoundationChat.app
xcrun simctl launch 409925DC-4CAC-4370-A567-28B1DF07717E com.gustavo.FoundationChat

# iPhone físico (firma automática con team AHG445RV5X)
xcodebuild -project FoundationChat.xcodeproj -scheme FoundationChat \
  -destination 'id=00008150-001518693AC0401C' -derivedDataPath build -allowProvisioningUpdates build
xcrun devicectl device install app --device 00008150-001518693AC0401C build/Build/Products/Debug-iphoneos/FoundationChat.app
```

Push a GitHub: la credencial HTTPS del keychain da 403, usar la de `gh` solo para ese comando:
```bash
git -c credential.helper= -c 'credential.helper=!gh auth git-credential' push
```

## Entorno (importante)

- **El runtime iOS del simulador debe coincidir con la versión mayor de macOS del host.** Con macOS 27, un simulador iOS 26.x falla con `GenerationError -1` / "Asset … not found in Model Catalog" aunque todo lo demás esté bien. Usar el simulador "iPhone 17 Pro (iOS 27)".
- El simulador usa el modelo del Mac; el Mac necesita Apple Intelligence activo. Probar el modelo directo en el host con un script Swift (`swiftc -parse-as-library`) aísla si el problema es del Mac o del simulador.
- Swift 6 con concurrencia estricta, deployment target iOS 26.

## Arquitectura

`FoundationChatApp` es un `TabView` con tres pestañas independientes, cada una con su propia `LanguageModelSession`:

- **Chat** (`ContentView` + `ChatViewModel`): el view model `@MainActor @Observable` es dueño de la sesión y la recrea con `ChatViewModel.makeSession()`, que registra las tools (`PantryTool`, `DateTimeTool`). Toda creación de sesión del chat debe pasar por ahí (o incluir las tools) para no perderlas. Maneja streaming, `prewarm()`, y ante `exceededContextWindowSize` llama a `condenseContext()`: resume con una sesión aparte, crea una sesión nueva con el resumen en las instructions y reintenta el prompt. `TranscriptView` muestra `session.transcript`.
- **Recetas** (`RecipeView` + `Recipe`): guided generation con `@Generable`/`@Guide`, stream de `Recipe.PartiallyGenerated`.
- **Opciones** (`OptionsView`): arma `GenerationOptions` y crea una sesión nueva por cada generación para que las respuestas no se influyan.

`Tools.swift`: las tools corren fuera del main actor; reportan a `ToolLog.shared` (singleton `@MainActor`) con `await`, y `ContentView` lo muestra bajo el chat.

Errores: todo `catch` de llamadas al modelo usa `ModelErrors.message(for:)` y, para el overflow de contexto, `ModelErrors.isContextOverflow(_:)`. iOS 27 lanza `LanguageModelError` en vez de `LanguageModelSession.GenerationError`; `ModelErrors.swift` maneja ambos, no hacer `catch` directo sobre casos de `GenerationError`.

Las instructions y descriptions están en español. El modelo es chico (~3B): no confiar en el prompt para restricciones duras (eligió un argumento de enum equivocado pese a instrucciones explícitas); restringir en código con `@Generable`/`@Guide`.
