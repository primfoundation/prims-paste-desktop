import SwiftUI

/// Official Prim folio: spine plus page with a folded corner.
/// Geometry from prim.brand `assets/logos/folio.svg` viewBox 0 0 200 200.
struct FolioMark: View {
    var fill: Color = Ink.ink

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 200
            let ox = (size.width - 200 * s) / 2
            let oy = (size.height - 200 * s) / 2
            let spine = Path(CGRect(x: ox + 56 * s, y: oy + 30 * s, width: 16 * s, height: 140 * s))
            var page = Path()
            page.move(to: CGPoint(x: ox + 72 * s, y: oy + 30 * s))
            page.addLine(to: CGPoint(x: ox + 122 * s, y: oy + 30 * s))
            page.addLine(to: CGPoint(x: ox + 146 * s, y: oy + 54 * s))
            page.addLine(to: CGPoint(x: ox + 146 * s, y: oy + 170 * s))
            page.addLine(to: CGPoint(x: ox + 72 * s, y: oy + 170 * s))
            page.closeSubpath()
            ctx.fill(spine, with: .color(fill))
            ctx.fill(page, with: .color(fill))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("Prims")
    }
}
