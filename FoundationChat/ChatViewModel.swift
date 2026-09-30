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

    static let instructions = """
        Eres un asistente de cocina amable. Responde en español, de forma breve y clara.
        Cuando el usuario pregunte qué cocinar o qué ingredientes tiene, llama de inmediato \
        a consultarDespensa con categoria "todo". No le preguntes al usuario; consulta primero \
        y luego sugiere una receta concreta usando esos ingredientes.
        Si necesitas saber la fecha u hora, llama a fechaHoraActual sin preguntar.
        """

    static func makeSession() -> LanguageModelSession {
        LanguageModelSession(tools: [PantryTool(), DateTimeTool()], instructions: instructions)
    }

    private var session = ChatViewModel.makeSession()

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
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            session = Self.makeSession()
            messages[index].text = "⚠️ Se llenó el contexto; empecé una sesión nueva. Vuelve a preguntar."
        } catch {
            messages[index].text = "⚠️ Error: \(error.localizedDescription)"
        }
    }

    func reset() {
        messages.removeAll()
        ToolLog.shared.entries.removeAll()
        session = Self.makeSession()
    }
}
