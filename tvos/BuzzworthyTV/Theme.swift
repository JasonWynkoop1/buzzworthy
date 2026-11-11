import SwiftUI
import UIKit
import CoreText
import CoreImage.CIFilterBuiltins

enum Theme {
    static let bg = Color(hex: "#12082b")
    static let bg2 = Color(hex: "#2a0f5c")
    static let panel = Color.white.opacity(0.07)
    static let text = Color(hex: "#f6f1ff")
    static let muted = Color(hex: "#b9a8e0")
    static let hot = Color(hex: "#ff5d8f")
    static let sun = Color(hex: "#ffd166")
    static let cool = Color(hex: "#4cc9f0")
    static let good = Color(hex: "#06d6a0")
    static let bad = Color(hex: "#ff5d5d")
    static let tile1 = Color(hex: "#3d1d8f")
    static let tile2 = Color(hex: "#251060")
    static let dark = Color(hex: "#1a1033")

    static let brand = LinearGradient(colors: [hot, sun, cool], startPoint: .leading, endPoint: .trailing)

    /// Loads the bundled Bungee font file once.
    private static let fontLoaded: Bool = {
        guard let url = Bundle.main.url(forResource: "Bungee-Regular", withExtension: "ttf") else { return false }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        return UIFont(name: "Bungee-Regular", size: 20) != nil
    }()

    /// The chunky display font (Bungee), with a bold rounded fallback.
    static func display(_ size: CGFloat) -> Font {
        if fontLoaded { return .custom("Bungee-Regular", size: size) }
        return .system(size: size, weight: .black, design: .rounded)
    }
    static func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }
}

/// Gradient-filled text, like the logo and big titles on the web page.
struct GradientText: View {
    let text: String
    let size: CGFloat
    var gradient: LinearGradient = Theme.brand

    var body: some View {
        Text(text)
            .font(Theme.display(size))
            .multilineTextAlignment(.center)
            .foregroundStyle(gradient)
    }
}

/// A button look that works with the Siri Remote: it grows and glows when focused.
struct TVButtonStyle: ButtonStyle {
    var fill: Color = Theme.panel
    var focusedFill: Color = Theme.hot
    var corner: CGFloat = 16

    func makeBody(configuration: Configuration) -> some View {
        Inner(configuration: configuration, fill: fill, focusedFill: focusedFill, corner: corner)
    }

    private struct Inner: View {
        let configuration: ButtonStyle.Configuration
        let fill: Color
        let focusedFill: Color
        let corner: CGFloat
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .background(RoundedRectangle(cornerRadius: corner).fill(focused ? focusedFill : fill))
                .overlay(RoundedRectangle(cornerRadius: corner).stroke(Color.white.opacity(focused ? 0.9 : 0.15), lineWidth: focused ? 4 : 1))
                .scaleEffect(configuration.isPressed ? 0.96 : (focused ? 1.06 : 1))
                .shadow(color: focused ? focusedFill.opacity(0.6) : .clear, radius: 18)
                .animation(.easeOut(duration: 0.15), value: focused)
        }
    }
}

enum QRCode {
    static func image(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
