import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            CallScreen()
                .tabItem {
                    Image(systemName: "mic.circle")
                    Text("Record")
                }
                .tag(0)
                .accessibilityIdentifier("record_tab")
                .accessibilityLabel("Record")
                .accessibilityHint("Record a new voice capsule")
            
            CapsuleListView()
                .tabItem {
                    Image(systemName: "list.bullet")
                    Text("My Capsules")
                }
                .tag(1)
                .accessibilityIdentifier("capsules_tab")
                .accessibilityLabel("My Capsules")
                .accessibilityHint("View your saved voice capsules")
        }
        .accentColor(.blue)
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    ContentView()
}