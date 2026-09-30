import SwiftUI
import FoundationModels

/// Paso 1 del flujo: verificar disponibilidad → recién ahí crear sesión → enviar prompt.
/// Envuelve cualquier pantalla que use el modelo; se re-evalúa cada vez que se muestra.
struct AvailabilityGate<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        switch ModelAvailability.current {
        case .available:
            content()
        case .unavailable(.deviceNotEligible):
            UnavailableFeatureView(
                title: "Dispositivo no compatible",
                description: "Este dispositivo no soporta Apple Intelligence.",
                systemImage: "exclamationmark.triangle")
        case .unavailable(.appleIntelligenceNotEnabled):
            UnavailableFeatureView(
                title: "Apple Intelligence desactivado",
                description: "Actívalo en Ajustes para usar esta función.",
                systemImage: "gear")
        case .unavailable(.modelNotReady):
            UnavailableFeatureView(
                title: "Modelo no listo",
                description: "Se está preparando el modelo. Intenta de nuevo en un rato.",
                systemImage: "clock.arrow.circlepath")
        case .unavailable:
            // Catch-all: razones que Apple agregue en versiones futuras.
            UnavailableFeatureView(
                title: "Función no disponible",
                description: "Esta función no está disponible por ahora.",
                systemImage: "questionmark.circle")
        }
    }
}

struct UnavailableFeatureView: View {
    let title: String
    let description: String
    let systemImage: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(description))
    }
}

enum ModelAvailability {
    static var current: SystemLanguageModel.Availability {
        #if DEBUG
        // Para probar cada caso sin tocar el scheme:
        //   SIMCTL_CHILD_FM_SIMULATE=notEnabled xcrun simctl launch <UDID> com.gustavo.FoundationChat
        switch ProcessInfo.processInfo.environment["FM_SIMULATE"] {
        case "notEligible": return .unavailable(.deviceNotEligible)
        case "notEnabled": return .unavailable(.appleIntelligenceNotEnabled)
        case "notReady": return .unavailable(.modelNotReady)
        default: break
        }
        #endif
        return SystemLanguageModel.default.availability
    }
}
