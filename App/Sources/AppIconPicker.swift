import Model
import SwiftUI

/// Settings ▸ Appearance ▸ App Icon: the choices in two rows of four, each in
/// the rendition of the window's appearance, the chosen one ringed in the
/// accent colour.
struct AppIconPicker: View {
    @Binding var selection: AppIconChoice
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 12) {
            ForEach(AppIconChoice.allCases, id: \.self) { choice in
                AppIconCell(choice: choice, dark: colorScheme == .dark, isSelected: selection == choice) {
                    selection = choice
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("App Icon")
    }
}

private struct AppIconCell: View {
    let choice: AppIconChoice
    let dark: Bool
    let isSelected: Bool
    let choose: () -> Void

    /// The image's frame; the icon's shape is 824 of its 1024 px (the macOS
    /// icon grid, `scripts/render-app-icons.sh`) with continuous corners.
    private static let side: CGFloat = 64
    private static let shape = side * 824 / 1024
    private static let shapeRadius = shape * 0.225
    private static let ringGap: CGFloat = 2.5
    private static let ringWidth: CGFloat = 2.5

    var body: some View {
        Button(action: choose) {
            VStack(spacing: 4) {
                ZStack {
                    if let image = AppIconImages.image(choice, dark: dark) {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                    }
                    if isSelected {
                        // The ring's outer edge, a gap and a line width around the shape.
                        let outset = Self.ringGap + Self.ringWidth
                        RoundedRectangle(cornerRadius: Self.shapeRadius + outset, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: Self.ringWidth)
                            .frame(width: Self.shape + 2 * outset, height: Self.shape + 2 * outset)
                    }
                }
                .frame(width: Self.side, height: Self.side)
                Text(choice.displayName)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
