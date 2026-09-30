import Foundation
import FoundationModels

/// Traduce los errores del framework a mensajes que el usuario entiende.
/// Todos los `respond` / `streamResponse` de la app deberían pasar por aquí.
enum ModelErrors {
    static func message(for error: Error) -> String {
        // Un error lanzado dentro de una tool llega envuelto en ToolCallError.
        if let toolError = error as? LanguageModelSession.ToolCallError {
            return "🔧 Falló la herramienta «\(toolError.tool.name)». Intenta de nuevo."
        }
        // iOS 27+ lanza el tipo nuevo LanguageModelError; iOS 26 lanza GenerationError.
        if #available(iOS 27, *), let error = error as? LanguageModelError {
            return message(for: error)
        }
        guard let error = error as? LanguageModelSession.GenerationError else {
            return "⚠️ Error inesperado: \(error.localizedDescription)"
        }
        switch error {
        case .guardrailViolation:
            // Los guardrails de seguridad de Apple bloquearon el prompt o la respuesta.
            return "🛡️ No puedo responder eso. Prueba reformulando la pregunta."
        case .refusal:
            // El modelo decidió no responder (distinto del guardrail).
            return "🙅 El modelo prefirió no responder esa solicitud."
        case .unsupportedLanguageOrLocale:
            return "🌐 Ese idioma no está soportado por el modelo on-device."
        case .exceededContextWindowSize:
            return "🗜️ La conversación es muy larga. Empieza una nueva."
        case .assetsUnavailable:
            return "⬇️ El modelo no está disponible todavía (¿se está descargando?)."
        case .rateLimited:
            return "⏳ Demasiadas solicitudes seguidas. Espera un momento."
        case .concurrentRequests:
            return "⏳ Ya hay una respuesta en curso. Espera a que termine."
        case .decodingFailure, .unsupportedGuide:
            return "🧩 El modelo no pudo generar el formato esperado. Intenta de nuevo."
        @unknown default:
            return "⚠️ Error del modelo: \(error.localizedDescription)"
        }
    }

    @available(iOS 27, *)
    private static func message(for error: LanguageModelError) -> String {
        switch error {
        case .guardrailViolation: "🛡️ No puedo responder eso. Prueba reformulando la pregunta."
        case .refusal: "🙅 El modelo prefirió no responder esa solicitud."
        case .unsupportedLanguageOrLocale: "🌐 Ese idioma no está soportado por el modelo on-device."
        case .contextSizeExceeded: "🗜️ La conversación es muy larga. Empieza una nueva."
        case .rateLimited: "⏳ Demasiadas solicitudes seguidas. Espera un momento."
        case .timeout: "⌛ El modelo tardó demasiado. Intenta de nuevo."
        case .unsupportedGenerationGuide, .unsupportedCapability, .unsupportedTranscriptContent:
            "🧩 El modelo no pudo generar el formato esperado. Intenta de nuevo."
        @unknown default: "⚠️ Error del modelo: \(error.localizedDescription)"
        }
    }

    /// ¿El error indica que se llenó la ventana de contexto? (cubre iOS 26 y 27)
    static func isContextOverflow(_ error: Error) -> Bool {
        if #available(iOS 27, *), let error = error as? LanguageModelError,
           case .contextSizeExceeded = error {
            return true
        }
        if let error = error as? LanguageModelSession.GenerationError,
           case .exceededContextWindowSize = error {
            return true
        }
        return false
    }
}

extension SystemLanguageModel {
    /// ¿El modelo soporta el idioma actual del dispositivo?
    var supportsCurrentLocale: Bool {
        supportsLocale(Locale.current)
    }
}
