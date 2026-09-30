import Foundation
import FoundationModels
import Observation

struct Message: Identifiable {
    let id = UUID()
    let isUser: Bool
    var text: String
}

@MainActor
@Observable
final class ChatViewModel {
    var messages: [Message] = []
    var input = ""
    var isResponding = false

    static let instructions = "Asistente de cocina. Responde en español, breve."

    static func makeSession() -> LanguageModelSession {
        LanguageModelSession(tools: [PantryTool(), DateTimeTool()], instructions: instructions)
    }

    private(set) var session = ChatViewModel.makeSession()

    /// Carga el modelo en memoria antes del primer prompt → menos latencia en la 1.ª respuesta.
    func prewarm() {
        session.prewarm()
    }

    /// Estado del modelo on-device (Apple Intelligence debe estar activo).
    var availability: SystemLanguageModel.Availability {
        SystemLanguageModel.default.availability
    }

    func send() async {
        let prompt = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isResponding else { return }
        input = ""
        messages.append(Message(isUser: true, text: prompt))
        messages.append(Message(isUser: false, text: ""))
        let index = messages.count - 1
        isResponding = true
        defer { isResponding = false }

        do {
            // Streaming: cada snapshot trae la respuesta acumulada hasta ahora.
            for try await snapshot in session.streamResponse(to: prompt) {
                messages[index].text = snapshot.content
            }
        } catch where ModelErrors.isContextOverflow(error) {
            // Contexto lleno: resumimos la conversación, abrimos una sesión nueva
            // "sembrada" con ese resumen y reintentamos el mismo prompt.
            await condenseContext()
            do {
                for try await snapshot in session.streamResponse(to: prompt) {
                    messages[index].text = snapshot.content
                }
            } catch {
                messages[index].text = ModelErrors.message(for: error)
            }
        } catch {
            messages[index].text = ModelErrors.message(for: error)
        }
    }

    /// Resume la conversación en una sesión aparte y crea una sesión nueva con ese resumen.
    func condenseContext() async {
        let history = messages
            .filter { !$0.text.isEmpty }
            .map { ($0.isUser ? "Usuario: " : "Asistente: ") + $0.text }
            .joined(separator: "\n")

        var summary = ""
        if !history.isEmpty {
            let summarizer = LanguageModelSession(
                instructions: "Resume conversaciones en español en máximo 3 frases, conservando datos clave."
            )
            summary = (try? await summarizer.respond(to: history).content) ?? ""
        }

        let seeded = summary.isEmpty
            ? Self.instructions
            : Self.instructions + "\n\nResumen de la conversación anterior: " + summary
        session = LanguageModelSession(tools: [PantryTool(), DateTimeTool()], instructions: seeded)
        messages.append(Message(isUser: false, text: "🗜️ Contexto resumido: \(summary.isEmpty ? "(vacío)" : summary)"))
    }

    func reset() {
        messages.removeAll()
        ToolLog.shared.entries.removeAll()
        session = Self.makeSession()
    }
}
