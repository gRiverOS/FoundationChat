import FoundationModels

// @Generable: el modelo genera directamente este struct (guided generation),
// sin tener que parsear JSON a mano.
@Generable
struct Recipe {
    @Guide(description: "Nombre atractivo de la receta")
    var name: String

    @Guide(description: "Minutos totales de preparación", .range(5...180))
    var minutes: Int

    @Guide(description: "Nivel de dificultad")
    var difficulty: Difficulty

    @Guide(description: "Ingredientes con cantidad", .count(3...10))
    var ingredients: [String]

    @Guide(description: "Pasos de preparación, uno por elemento", .count(3...8))
    var steps: [String]
}

@Generable
enum Difficulty: String {
    case facil, media, dificil
}
