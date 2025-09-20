import SwiftUI

// Global gradient palette for Spinder
enum Palette {
    static let grad = LinearGradient(
        colors: [
            Color(hue: 0.76, saturation: 0.72, brightness: 0.88), // lavender
            Color(hue: 0.86, saturation: 0.60, brightness: 0.92), // pink-violet
            Color(hue: 0.64, saturation: 0.55, brightness: 0.90)  // periwinkle
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let aura1 = LinearGradient(
        colors: [Color.purple.opacity(0.30), Color.pink.opacity(0.18)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let aura2 = LinearGradient(
        colors: [Color.blue.opacity(0.20), Color.purple.opacity(0.24)],
        startPoint: .bottomLeading, endPoint: .topTrailing
    )
}

// Gradient text sugar
extension View {
    func gradientText() -> some View { self.foregroundStyle(Palette.grad) }
}

// Glassy gradient-stroke button (used in onboarding + sheet)
struct GlassGradientButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 26).padding(.vertical, 14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.grad, lineWidth: 2))
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}
