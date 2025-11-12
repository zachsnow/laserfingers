import SwiftUI

struct LevelEditorView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @ObservedObject var viewModel: LevelEditorViewModel
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.95)
                .ignoresSafeArea()
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("Level Editor")
                        .font(.largeTitle.bold())
                    Text(viewModel.headerTitle)
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.white.opacity(0.8))
                    Text(viewModel.headerSubtitle)
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)
                Spacer()
                LaserButton(title: "Exit Editor", style: .secondary) {
                    coordinator.exitLevelEditor()
                }
            }
            .foregroundColor(.white)
            .padding()
        }
    }
}
