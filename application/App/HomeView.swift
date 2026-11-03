import SwiftUI

struct HomeView: View {
#if DEBUG
    @State private var showsProvider = ProcessInfo.processInfo.arguments.contains("-provider007")
    @State private var showsSpike = ProcessInfo.processInfo.arguments.contains("-spike004")
#endif
    var body: some View {
        LibraryView()
#if DEBUG
        .overlay(alignment: .bottomTrailing) {
            Menu("Debug", systemImage: "hammer") {
                Button("Ink + object spike (004)") { showsSpike = true }
                Button("Qwen vision test (007)") { showsProvider = true }
            }
            .padding()
        }
        .fullScreenCover(isPresented: $showsProvider) { QwenDebugView() }
        .fullScreenCover(isPresented: $showsSpike) {
            NavigationStack {
                InkObjectSpikeView()
                    .navigationTitle("004 · Ink + objects")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showsSpike = false }
                        }
                    }
            }
        }
#endif
    }
}

#Preview {
    HomeView()
}
