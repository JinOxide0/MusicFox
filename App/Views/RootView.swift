import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        @Bindable var player = model.player

        ZStack(alignment: .bottom) {
            AppBackground()

            TabView(selection: $model.tab) {
                HomeView()
                    .tag(AppTab.home)
                    .tabItem { Label("首页", systemImage: "house.fill") }

                LibraryView()
                    .tag(AppTab.library)
                    .tabItem { Label("音乐库", systemImage: "square.stack.fill") }

                FavoritesView()
                    .tag(AppTab.favorites)
                    .tabItem { Label("收藏", systemImage: "heart.fill") }

                SourcesView()
                    .tag(AppTab.sources)
                    .tabItem { Label("音源", systemImage: "bolt.horizontal.fill") }

                SettingsView()
                    .tag(AppTab.settings)
                    .tabItem { Label("设置", systemImage: "gearshape.fill") }
            }
            .tint(Palette.cyan)
            .toolbarBackground(Palette.background.opacity(0.96), for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)

            if player.hasCurrent {
                MiniPlayer()
                    .padding(.horizontal, 12)
                    .padding(.bottom, 56)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if model.isLoading {
                LoadingOverlay()
            }
        }
        .animation(.easeInOut(duration: 0.22), value: player.hasCurrent)
        .fullScreenCover(isPresented: $player.showNowPlaying) {
            NowPlayingView()
        }
        .overlay(alignment: .top) {
            if let status = model.importStatus {
                ImportStatusBar(text: status)
            }
        }
        .alert(
            "出错了",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .preferredColorScheme(.dark)
    }
}
