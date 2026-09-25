import SwiftUI

@main
struct DemoApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                ConfigURLTesterView()
                    .tabItem { Label("Config URL", systemImage: "link") }
                ContentView()
                    .tabItem { Label("Universal Consent", systemImage: "person.2") }
            }
        }
    }
}
