import SwiftUI

@main
struct FoundationChatApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                Tab("Chat", systemImage: "bubble.left.and.bubble.right") { ContentView() }
                Tab("Recetas", systemImage: "fork.knife") { RecipeView() }
            }
        }
    }
}
