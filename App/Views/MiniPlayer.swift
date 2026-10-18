import SwiftUI

struct MiniPlayer: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.player.hasCurrent {
            VStack(spacing: 0) {
                HStack(spacing: 11) {
                    CoverArt(url: model.player.coverURL, size: 43, corner: 11)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.player.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.textPrimary)
                            .lineLimit(1)
                        HStack(spacing: 5) {
                            if model.player.currentRemote != nil {
                                TagPill(text: "在线", color: Palette.violet)
                            }
                            Text(model.player.artist)
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                    Button {
                        model.player.toggle()
                    } label: {
                        Image(systemName: model.player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Palette.textPrimary)
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                    Button {
                        model.player.next()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Palette.textSecondary)
                            .frame(width: 30, height: 34)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.top, 9)
                .padding(.bottom, 8)

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule()
                            .fill(Palette.accentGradient)
                            .frame(width: proxy.size.width * progressFraction)
                    }
                }
                .frame(height: 2)
                .padding(.horizontal, 12)
                .padding(.bottom, 7)
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Palette.stroke, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
            .contentShape(Rectangle())
            .onTapGesture {
                model.player.showNowPlaying = true
            }
        }
    }

    private var progressFraction: Double {
        guard model.player.duration > 0, model.player.progress.isFinite else { return 0 }
        return min(1, max(0, model.player.progress / model.player.duration))
    }
}
