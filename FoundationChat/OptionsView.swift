import SwiftUI
import FoundationModels

struct OptionsView: View {
    enum SamplingMode: String, CaseIterable, Identifiable {
        case greedy = "Greedy", topK = "Top-K", topP = "Top-P"
        var id: Self { self }
    }

    @State private var prompt = "Inventa un nombre para una sanguchería en Valparaíso."
    @State private var temperature = 1.0
    @State private var mode = SamplingMode.topK
    @State private var topK = 40
    @State private var topP = 0.9
    @State private var maxTokens = 60
    @State private var results: [String] = []
    @State private var isRunning = false

    // GenerationOptions controla CÓMO el modelo elige cada token.
    private var options: GenerationOptions {
        let sampling: GenerationOptions.SamplingMode = switch mode {
        case .greedy: .greedy                                   // siempre el token más probable → determinista
        case .topK: .random(top: topK)                          // sortea entre los K más probables
        case .topP: .random(probabilityThreshold: topP)         // sortea entre los que suman P de probabilidad
        }
        return GenerationOptions(
            samplingMode: sampling,
            temperature: temperature,                           // >1 más creativo, <1 más conservador
            maximumResponseTokens: maxTokens                    // corta la respuesta al llegar al límite
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Prompt") {
                    TextField("Prompt", text: $prompt, axis: .vertical)
                }
                Section("Sampling") {
                    Picker("Modo", selection: $mode) {
                        ForEach(SamplingMode.allCases) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    if mode == .topK {
                        Stepper("Top-K: \(topK)", value: $topK, in: 1...100)
                    }
                    if mode == .topP {
                        LabeledContent("Top-P: \(topP, format: .number.precision(.fractionLength(2)))") {
                            Slider(value: $topP, in: 0.1...1.0)
                        }
                    }
                    LabeledContent("Temperature: \(temperature, format: .number.precision(.fractionLength(1)))") {
                        Slider(value: $temperature, in: 0.0...2.0)
                    }
                    .disabled(mode == .greedy)
                    Stepper("Máx. tokens: \(maxTokens)", value: $maxTokens, in: 10...300, step: 10)
                }
                Section {
                    Button(isRunning ? "Generando…" : "Generar 3 respuestas") {
                        Task { await run() }
                    }
                    .disabled(isRunning || prompt.isEmpty)
                }
                if !results.isEmpty {
                    Section("Resultados") {
                        ForEach(Array(results.enumerated()), id: \.offset) { i, text in
                            Text("\(i + 1). \(text)")
                        }
                    }
                }
            }
            .navigationTitle("Opciones")
        }
    }

    private func run() async {
        isRunning = true
        results = []
        defer { isRunning = false }
        for _ in 0..<3 {
            // Sesión nueva cada vez: así las respuestas no se influyen entre sí.
            let session = LanguageModelSession(instructions: "Responde en español, en una sola frase.")
            do {
                let response = try await session.respond(to: prompt, options: options)
                results.append(response.content)
            } catch {
                results.append(ModelErrors.message(for: error))
            }
        }
    }
}
