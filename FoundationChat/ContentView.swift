import SwiftUI
import FoundationModels

struct ContentView: View {
    @State private var vm = ChatViewModel()
    @State private var showTranscript = false

    var body: some View {
        NavigationStack {
            Group {
                switch vm.availability {
                case .available:
                    chat
                case .unavailable(let reason):
                    ContentUnavailableView(
                        "Modelo no disponible",
                        systemImage: "brain",
                        description: Text(describe(reason))
                    )
                }
            }
            .navigationTitle("Foundation Chat")
            .toolbar {
                Menu("Sesión", systemImage: "ellipsis.circle") {
                    Button("Ver transcript", systemImage: "list.bullet.rectangle") { showTranscript = true }
                    Button("Simular contexto lleno", systemImage: "arrow.down.right.and.arrow.up.left") {
                        Task { await vm.condenseContext() }
                    }
                    Button("Nueva conversación", systemImage: "square.and.pencil") { vm.reset() }
                }
                .disabled(vm.isResponding)
            }
            .sheet(isPresented: $showTranscript) {
                TranscriptView(transcript: vm.session.transcript)
            }
            .onAppear { vm.prewarm() }
        }
    }

    private var chat: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(vm.messages) { msg in
                            bubble(msg).id(msg.id)
                        }
                    }
                    .padding()
                    if !ToolLog.shared.entries.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(ToolLog.shared.entries.enumerated()), id: \.offset) { _, e in
                                Text(e).font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                    }
                }
                .onChange(of: vm.messages.last?.text) {
                    if let id = vm.messages.last?.id { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
            HStack {
                TextField("Pregúntale algo…", text: $vm.input, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await vm.send() } }
                Button {
                    Task { await vm.send() }
                } label: {
                    Image(systemName: vm.isResponding ? "hourglass" : "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(vm.isResponding || vm.input.isEmpty)
            }
            .padding()
        }
    }

    private func bubble(_ msg: Message) -> some View {
        HStack {
            if msg.isUser { Spacer(minLength: 40) }
            Text(msg.text.isEmpty ? "…" : msg.text)
                .padding(10)
                .background(msg.isUser ? Color.accentColor : Color.gray.opacity(0.2),
                            in: .rect(cornerRadius: 14))
                .foregroundStyle(msg.isUser ? .white : .primary)
            if !msg.isUser { Spacer(minLength: 40) }
        }
    }

    private func describe(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible: "Este dispositivo no soporta Apple Intelligence."
        case .appleIntelligenceNotEnabled: "Activa Apple Intelligence en Ajustes (en el simulador lo toma de tu Mac)."
        case .modelNotReady: "El modelo se está descargando. Intenta en un rato."
        @unknown default: "Razón desconocida."
        }
    }
}
