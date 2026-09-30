import SwiftUI
import FoundationModels

/// Muestra lo que la sesión "recuerda": todo esto ocupa espacio en la ventana de contexto.
struct TranscriptView: View {
    let transcript: Transcript

    var body: some View {
        NavigationStack {
            List(Array(transcript.enumerated()), id: \.offset) { _, entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(label(for: entry)).font(.caption.bold()).foregroundStyle(.secondary)
                    Text(String(describing: entry)).font(.footnote).lineLimit(6)
                }
            }
            .navigationTitle("Transcript (\(transcript.count))")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func label(for entry: Transcript.Entry) -> String {
        switch entry {
        case .instructions: "INSTRUCTIONS"
        case .prompt: "PROMPT"
        case .response: "RESPONSE"
        case .toolCalls: "TOOL CALLS"
        case .toolOutput: "TOOL OUTPUT"
        @unknown default: "OTRO"
        }
    }
}
