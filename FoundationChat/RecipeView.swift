import SwiftUI
import FoundationModels

struct RecipeView: View {
    @State private var ingredients = "pollo, arroz, limón"
    // PartiallyGenerated: versión con todas las propiedades opcionales,
    // que se va llenando a medida que llegan los snapshots.
    @State private var recipe: Recipe.PartiallyGenerated?
    @State private var isGenerating = false
    @State private var errorText: String?

    private let session = LanguageModelSession(
        instructions: "Eres un chef chileno. Crea recetas caseras y simples. Responde en español."
    )

    var body: some View {
        NavigationStack {
            Form {
                Section("¿Qué tienes en el refri?") {
                    TextField("Ingredientes", text: $ingredients, axis: .vertical)
                    Button(isGenerating ? "Generando…" : "Generar receta") {
                        Task { await generate() }
                    }
                    .disabled(isGenerating || ingredients.isEmpty)
                }
                if let errorText {
                    Text(errorText).foregroundStyle(.red)
                }
                if let recipe {
                    Section(recipe.name ?? "…") {
                        if let minutes = recipe.minutes {
                            Label("\(minutes) min", systemImage: "clock")
                        }
                        if let difficulty = recipe.difficulty {
                            Label(difficulty.rawValue.capitalized, systemImage: "chart.bar")
                        }
                    }
                    Section("Ingredientes") {
                        ForEach(recipe.ingredients ?? [], id: \.self) { Text("• \($0)") }
                    }
                    Section("Pasos") {
                        ForEach(Array((recipe.steps ?? []).enumerated()), id: \.offset) { i, step in
                            Text("\(i + 1). \(step)")
                        }
                    }
                }
            }
            .navigationTitle("Recetas")
        }
    }

    private func generate() async {
        isGenerating = true
        errorText = nil
        recipe = nil
        defer { isGenerating = false }
        do {
            let stream = session.streamResponse(
                to: "Crea una receta usando: \(ingredients)",
                generating: Recipe.self
            )
            for try await snapshot in stream {
                recipe = snapshot.content
            }
        } catch {
            errorText = ModelErrors.message(for: error)
        }
    }
}
