import Foundation
import FoundationModels

// Tool: el modelo decide cuándo llamarla según `name` y `description`,
// y genera `Arguments` con guided generation (por eso es @Generable).
struct PantryTool: Tool {
    let name = "consultarDespensa"
    let description = "Ingredientes del usuario. Úsala antes de sugerir qué cocinar."

    @Generable
    struct Arguments {
        @Guide(description: "Usa todo si no se especifica")
        var categoria: Categoria
    }

    @Generable
    enum Categoria: String {
        case verduras, proteinas, abarrotes, todo
    }

    private let despensa: [Categoria: [String]] = [
        .verduras: ["3 tomates", "1 cebolla", "2 paltas", "1 lechuga"],
        .proteinas: ["500 g de carne molida", "6 huevos", "1 lata de atún"],
        .abarrotes: ["1 kg de arroz", "500 g de fideos", "aceite", "sal", "merkén"],
    ]

    func call(arguments: Arguments) async throws -> String {
        await ToolLog.shared.add("🔧 \(name)(categoria: \(arguments.categoria.rawValue))")
        let items = arguments.categoria == .todo
            ? despensa.values.flatMap { $0 }
            : despensa[arguments.categoria] ?? []
        return items.isEmpty ? "No hay nada en esa categoría." : items.joined(separator: ", ")
    }
}

struct DateTimeTool: Tool {
    let name = "fechaHoraActual"
    let description = "Fecha y hora actual."

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        await ToolLog.shared.add("🔧 \(name)()")
        return Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute()
            .locale(Locale(identifier: "es_CL")))
    }
}

/// Registro simple para ver en la UI qué tools llamó el modelo.
@MainActor
@Observable
final class ToolLog {
    static let shared = ToolLog()
    var entries: [String] = []

    func add(_ entry: String) {
        entries.append(entry)
    }
}
