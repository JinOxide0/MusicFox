import SwiftUI
import UIKit

enum Palette {
    static let background = Color(hex: 0x07090F)
    static let surface = Color(hex: 0x11151F)
    static let surfaceElevated = Color(hex: 0x181D2A)
    static let cyan = Color(hex: 0x22E3FF)
    static let violet = Color(hex: 0x8B5CFF)
    static let pink = Color(hex: 0xFF4FA3)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.56)
    static let textTertiary = Color.white.opacity(0.34)
    static let stroke = Color.white.opacity(0.08)
    static let accentGradient = LinearGradient(
        colors: [cyan, violet],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let softGradient = LinearGradient(
        colors: [cyan.opacity(0.22), violet.opacity(0.16)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

struct AppBackground: View {
    var body: some View {
        ZStack {
            Palette.background
            RadialGradient(
                colors: [Palette.violet.opacity(0.20), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 520
            )
            RadialGradient(
                colors: [Palette.cyan.opacity(0.12), .clear],
                center: .bottomLeading,
                startRadius: 0,
                endRadius: 460
            )
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.35)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

struct GlassPanel: ViewModifier {
    var corner: CGFloat = 24

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(Palette.surface.opacity(0.82))
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(Palette.stroke, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
    }
}

extension View {
    func glassPanel(corner: CGFloat = 24) -> some View {
        modifier(GlassPanel(corner: corner))
    }
}

struct CoverArt: View {
    let url: URL?
    var size: CGFloat = 52
    var corner: CGFloat = 13

    var body: some View {
        Group {
            if let url, url.isFileURL, let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let url, !url.isFileURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        placeholder
                    case .empty:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        )
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [Palette.cyan.opacity(0.30), Palette.violet.opacity(0.42)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image("FoxMark")
                .resizable()
                .scaledToFit()
                .padding(size * 0.18)
                .opacity(0.85)
        }
    }
}

struct FoxMark: View {
    var size: CGFloat = 38

    var body: some View {
        Image("FoxMark")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

struct SectionHeader: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.textPrimary)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.cyan)
            }
        }
    }
}

struct SearchField: View {
    @Binding var text: String
    var placeholder: String = "搜索"

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.textTertiary)
            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 15))
                .foregroundStyle(Palette.textPrimary)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Palette.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Palette.surfaceElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Palette.stroke, lineWidth: 1)
        )
    }
}

struct PrimaryButton: View {
    let title: String
    var icon: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(Color(hex: 0x05060A))
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Palette.accentGradient, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct GhostButton: View {
    let title: String
    var icon: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(Palette.textPrimary)
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(Palette.surfaceElevated, in: Capsule())
            .overlay(Capsule().stroke(Palette.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct TagPill: View {
    let text: String
    var color: Color = Palette.cyan

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Palette.softGradient)
                    .frame(width: 92, height: 92)
                Image(systemName: icon)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(Palette.accentGradient)
            }
            Text(title)
                .font(.system(size: 19, weight: .bold, design: .rounded))
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
            if let actionTitle, let action {
                GhostButton(title: actionTitle, icon: "plus", action: action)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .padding(.horizontal, 24)
        .glassPanel(corner: 22)
    }
}

struct LoadingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.28).ignoresSafeArea()
            HStack(spacing: 12) {
                ProgressView()
                    .tint(Palette.cyan)
                Text("正在整理…")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Palette.stroke, lineWidth: 1))
        }
    }
}

struct ImportStatusBar: View {
    let text: String

    var body: some View {
        HStack(spacing: 9) {
            ProgressView()
                .tint(Palette.cyan)
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Palette.stroke, lineWidth: 1))
        .padding(.top, 6)
    }
}
