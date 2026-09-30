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

    /// Resumen estructurado: extraer datos concretos funciona mejor que pedir texto libre.
    @Generable
    struct ConversationSummary {
        @Guide(description: "Datos del usuario mencionados: nombre, dieta, gustos, alergias", .count(0...6))
        var userFacts: [String]
        @Guide(description: "Tema de la conversación en pocas palabras")
        var topic: String
    }

    /// Resume la conversación en una sesión aparte y crea una sesión nueva con ese resumen.
    func condenseContext() async {
        let history = messages
            .filter { !$0.text.isEmpty }
            .map { ($0.isUser ? "Usuario: " : "Asistente: ") + $0.text }
            .joined(separator: "\n")

        var seeded = Self.instructions
        var note = "(vacío)"
        if !history.isEmpty {
            let summarizer = LanguageModelSession(
                instructions: "Extraes información de conversaciones. Responde en español."
            )
            // .greedy: el resumen debe ser estable, no creativo.
            if let summary = try? await summarizer.respond(
                to: history,
                generating: ConversationSummary.self,
                options: GenerationOptions(sampling: .greedy)
            ).content {
                let facts = summary.userFacts.joined(separator: "; ")
                seeded += "\nDatos del usuario: \(facts). Tema previo: \(summary.topic)."
                note = "datos = [\(facts)] · tema = \(summary.topic)"
            }
        }
        session = LanguageModelSession(tools: [PantryTool(), DateTimeTool()], instructions: seeded)
        messages.append(Message(isUser: false, text: "🗜️ Contexto resumido: \(note)"))
    }

    func reset() {
        messages.removeAll()
        ToolLog.shared.entries.removeAll()
        session = Self.makeSession()
    }
}
