import SwiftUI
import UIKit
import CoreText
import CoreImage.CIFilterBuiltins

// Look: a night-time game stage. Ink background, six bright color blocks
// (one per board column), chunky wide display type for names and money,
// a friendly geometric face for clues and labels.
enum Theme {
    static let ink = Color(hex: "#0E0F1A")
    static let stage = Color(hex: "#151729")
    static let surface = Color(hex: "#1C1F36")
    static let surface2 = Color(hex: "#272B4A")
    static let line = Color.white.opacity(0.10)
    static let text = Color(hex: "#F6F4EE")
    static let muted = Color(hex: "#9FA3C2")
    static let yellow = Color(hex: "#FFD23F")
    static let coral = Color(hex: "#FF5A5F")
    static let mint = Color(hex: "#3DDC97")
    static let good = mint
    static let bad = coral

    /// One color per board column.
    static let columns: [Color] = ["#FF5A5F", "#FF9F1C", "#FFD23F", "#3DDC97", "#3ABEFF", "#B388FF"].map { Color(hex: $0) }
    static func column(_ i: Int) -> Color { columns[((i % columns.count) + columns.count) % columns.count] }

    private static let fontsLoaded: Bool = {
        for name in ["Unbounded-Black", "Unbounded-Bold", "Outfit-Regular", "Outfit-SemiBold", "Outfit-ExtraBold"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
        return UIFont(name: "Unbounded-Black", size: 20) != nil && UIFont(name: "Outfit-Regular", size: 20) != nil
    }()

    /// Chunky display type: names, money, big titles.
    static func display(_ size: CGFloat) -> Font {
        fontsLoaded ? .custom("Unbounded-Black", fixedSize: size) : .system(size: size, weight: .black, design: .rounded)
    }
    static func title(_ size: CGFloat) -> Font {
        fontsLoaded ? .custom("Unbounded-Bold", fixedSize: size) : .system(size: size, weight: .bold, design: .rounded)
    }
    /// Clues, labels and everything else.
    static func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        guard fontsLoaded else { return .system(size: size, weight: weight) }
        let name: String
        if weight == .regular || weight == .light || weight == .thin || weight == .ultraLight {
            name = "Outfit-Regular"
        } else if weight == .medium || weight == .semibold {
            name = "Outfit-SemiBold"
        } else {
            name = "Outfit-ExtraBold"
        }
        return .custom(name, fixedSize: size)
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

/// The stage behind every screen: ink, two soft colored lights, a faint dot grid.
struct StageBackground: View {
    var body: some View {
        ZStack {
            Theme.ink
            RadialGradient(colors: [Theme.column(5).opacity(0.22), .clear], center: UnitPoint(x: 0.05, y: 0), startRadius: 0, endRadius: 900)
            RadialGradient(colors: [Theme.column(4).opacity(0.16), .clear], center: UnitPoint(x: 1, y: 1), startRadius: 0, endRadius: 900)
            Canvas { ctx, size in
                let step: CGFloat = 44
                var y: CGFloat = step / 2
                while y < size.height {
                    var x: CGFloat = step / 2
                    while x < size.width {
                        ctx.fill(Path(ellipseIn: CGRect(x: x - 1.5, y: y - 1.5, width: 3, height: 3)), with: .color(.white.opacity(0.05)))
                        x += step
                    }
                    y += step
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// Small all-caps label.
struct Eyebrow: View {
    let text: String
    var color: Color = Theme.muted
    var size: CGFloat = 22
    var body: some View {
        Text(text.uppercased())
            .font(Theme.body(size, .heavy))
            .kerning(size * 0.14)
            .foregroundColor(color)
    }
}

/// A player's colored circle with their first letter.
struct Avatar: View {
    let name: String
    let color: Color
    var size: CGFloat = 48
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay(
                Text(String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
                    .font(Theme.display(size * 0.44))
                    .foregroundColor(Theme.ink)
            )
    }
}

/// The room code as four color blocks.
struct CodeTiles: View {
    let code: String
    var size: CGFloat = 96
    var body: some View {
        HStack(spacing: size * 0.12) {
            ForEach(Array(code.enumerated()), id: \.offset) { i, ch in
                Text(String(ch))
                    .font(Theme.display(size * 0.56))
                    .foregroundColor(Theme.ink)
                    .frame(width: size, height: size)
                    .background(RoundedRectangle(cornerRadius: size * 0.2).fill(Theme.column([0, 2, 3, 4][i % 4])))
            }
        }
    }
}

/// A button look that works with the Siri Remote: it grows and brightens when focused.
struct TVButtonStyle: ButtonStyle {
    var fill: Color = Theme.surface2
    var text: Color = Theme.text
    var focusedFill: Color = Theme.text
    var focusedText: Color = Theme.ink
    var corner: CGFloat = 18

    func makeBody(configuration: Configuration) -> some View {
        Inner(configuration: configuration, style: self)
    }

    private struct Inner: View {
        let configuration: ButtonStyle.Configuration
        let style: TVButtonStyle
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .foregroundColor(focused ? style.focusedText : style.text)
                .background(
                    RoundedRectangle(cornerRadius: style.corner).fill(focused ? style.focusedFill : style.fill)
                        .shadow(color: .black.opacity(focused ? 0.45 : 0), radius: 16, y: 10)
                )
                .scaleEffect(configuration.isPressed ? 0.96 : (focused ? 1.07 : 1))
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
