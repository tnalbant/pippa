import AppKit
import SwiftUI

// Pippa's colors. Everything else uses system controls and system fonts.

enum Theme {
    static func dyn(_ light: NSColor, _ dark: NSColor) -> NSColor {
        NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light }
    }

    static func dynamic(light: NSColor, dark: NSColor) -> Color { Color(nsColor: dyn(light, dark)) }

    static func hex(_ v: Int, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: alpha)
    }

    private static let inkL = 0x202735, inkD = 0xEDF1F7
    private static func inkA(_ l: CGFloat, _ d: CGFloat) -> Color { dynamic(light: hex(inkL, l), dark: hex(inkD, d)) }
    private static func whiteA(_ l: CGFloat, _ d: CGFloat) -> Color { dynamic(light: hex(inkL, l), dark: NSColor(white: 1, alpha: d)) }

    // Text
    static let ink = inkA(1, 1)
    static let ink2 = inkA(0.78, 0.72)
    /// Hints: >= 4.5:1 on every light surface (white 5.3, glass ECECEC 4.9, green well 4.9) and dark (5.5 to 6.1).
    static let ink3 = inkA(0.68, 0.60)
    // Surfaces
    static let hair = whiteA(0.10, 0.10)
    static let fill = whiteA(0.045, 0.055)
    static let fill2 = whiteA(0.075, 0.095)
    static let fill3 = whiteA(0.13, 0.16)
    // Akzent
    static let accent = dynamic(light: hex(0x005BCD), dark: hex(0x80B8FF))
    static let accentFill = dynamic(light: hex(0x005BCD), dark: hex(0x1F6FE0))
    static let accentPress = dynamic(light: hex(0x0049A6), dark: hex(0x2B7CF0))
    static let accentTint = dynamic(light: hex(0x005BCD, 0.10), dark: hex(0x80B8FF, 0.14))
    static let accentTint2 = dynamic(light: hex(0x005BCD, 0.16), dark: hex(0x80B8FF, 0.22))
    static let highlight = dynamic(light: hex(0x005BCD, 0.15), dark: hex(0x80B8FF, 0.26))
    // Zustand
    static let ok = dynamic(light: hex(0x0D712C), dark: hex(0x45D97F))
    static let okTint = dynamic(light: hex(0x0D712C, 0.11), dark: hex(0x45D97F, 0.14))
    static let need = dynamic(light: hex(0x8A4600), dark: hex(0xFFB340))
    static let needTint = dynamic(light: hex(0xFF9F0A, 0.17), dark: hex(0xFF9F0A, 0.12))
    static let needDot = dynamic(light: hex(0xE08600), dark: hex(0xFFB340))
    // Same red as the figure's sad face (MarkPalette.destructive), so face and sign match.
    static let bad = dynamic(light: hex(0xC4001D), dark: hex(0xF89DA4))
    static let badTint = dynamic(light: hex(0xC4001D, 0.10), dark: hex(0xF89DA4, 0.14))
    // Calm chat surfaces. Color marks interaction, not the whole work area.
    static let chatTint = dyn(hex(0xFCFBF9, 0.98), hex(0x1B1B1D, 0.98))
    static let chatSidebar = dynamic(light: hex(0xF1F0ED), dark: hex(0x222224))
    // Neutral like the window around it: a blue cast here made the composer, step chips and receipts look bluish.
    static let chatCard = dynamic(light: hex(0xFFFFFF), dark: hex(0x262628))
    static let chatInset = dynamic(light: hex(0xF2F5FA), dark: hex(0x1B202A))
    static let chatBorder = dynamic(light: hex(0x202735, 0.10), dark: hex(0xEDF1F7, 0.12))
    static let chatUser = dynamic(light: hex(0xEEEDEA), dark: hex(0x303033))
}

extension Font {
    /// The card views' text style: system font at a fixed size.
    static func scaled(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .system(size: size, weight: weight, design: design)
    }
}

extension View {
    /// The frame of a result card under an answer.
    func resultCard() -> some View {
        frame(maxWidth: 520, alignment: .leading)
            .background(Theme.chatCard, in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.chatBorder, lineWidth: 0.5) }
    }
}

/// Chips that wrap onto the next line.
struct FlowRow: Layout {
    var spacing: CGFloat = 6
    /// No chip grows wider than this (long names truncate).
    var maxItemWidth: CGFloat = 170

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangement(width: proposal.width ?? 400, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = arrangement(width: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let frame = layout.frames[index]
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrangement(width: CGFloat, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let width = max(1, width)
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: min(maxItemWidth, width), height: nil))
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: y + rowHeight), frames)
    }
}
