import SwiftUI

@main
struct FoundationChatApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                Tab("Chat", systemImage: "bubble.left.and.bubble.right") { AvailabilityGate { ContentView() } }
                Tab("Recetas", systemImage: "fork.knife") { AvailabilityGate { RecipeView() } }
                Tab("Opciones", systemImage: "slider.horizontal.3") { AvailabilityGate { OptionsView() } }
            }
        }
    }
}
