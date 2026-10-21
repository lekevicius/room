import AppKit
import Design
import Model
import SwiftUI

/// The space creation and edit form (spec §B): name ("Space Name"), icon
/// (emoji or SF Symbol), up to three colour wells with the five algorithms,
/// and the profile. A SwiftUI leaf in an `NSHostingView` that takes the
/// list's place in the sidebar (it slides in like a space). Enter creates
/// or saves, Esc cancels.
@Observable
final class SpaceFormModel {
    enum Mode: Equatable {
        case create
        case edit(UUID)
    }

    typealias Focus = SpaceFormFocus

    let mode: Mode
    var name: String
    /// Emoji or SF Symbol name; `nil` = the default dot.
    var icon: String?
    /// Up to three wells; the first is the base colour.
    var wells: [Color]
    var algorithm: ThemeAlgorithm
    var opacity: Double
    var profileID: UUID
    var profiles: [Model.Profile]
    /// A profile the form will create on commit ("New Profile…").
    var newProfileName: String?
    var initialFocus: Focus
    /// The name used when the field is left empty.
    let placeholderName: String

    init(mode: Mode, space: Space?, profiles: [Model.Profile], defaultProfile: UUID, placeholderName: String, focus: Focus = .name) {
        self.mode = mode
        name = space?.name ?? ""
        icon = space?.icon
        wells = (space?.themeColors ?? []).compactMap(Self.color(hex:))
        algorithm = space?.themeAlgorithm ?? .analogous
        opacity = space?.themeOpacity ?? 0.5
        profileID = space?.profileID ?? defaultProfile
        self.profiles = profiles
        self.placeholderName = placeholderName
        initialFocus = focus
    }

    var title: String { mode == .create ? "New Space" : "Edit Space" }
    var commitTitle: String { mode == .create ? "Create" : "Save" }

    /// The wells as `#RRGGBB`.
    var themeColors: [String] { wells.compactMap(Self.hex(of:)) }

    /// What the window tint will show: the wells extended by the algorithm.
    var paletteColors: [Color] { ThemePalette.colors(themeColors, algorithm: algorithm).compactMap(Self.color(hex:)) }

    /// The colour a new well starts with: the algorithm's next hue from the base, or a calm blue.
    func addWell() {
        guard wells.count < ThemePalette.maxColors else { return }
        let derived = ThemePalette.colors(themeColors, algorithm: algorithm == .floating ? .triadic : algorithm)
        let next = derived.indices.contains(wells.count) ? derived[wells.count] : Palette.themeWellDefaultHex
        wells.append(Self.color(hex: next) ?? .blue)
    }

    static func color(hex: String) -> Color? {
        guard let hsl = HSLColor(hex: hex) else { return nil }
        let (red, green, blue) = hsl.rgb
        return Color(.sRGB, red: red, green: green, blue: blue)
    }

    static func hex(of color: Color) -> String? {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        return HSLColor(red: Double(rgb.redComponent), green: Double(rgb.greenComponent), blue: Double(rgb.blueComponent)).hex
    }
}

/// Which part of the space form has the focus when it opens (Change Icon…, Edit Theme…).
public enum SpaceFormFocus: Hashable, Sendable {
    case name, icon, theme
}

/// Curated choices for the icon picker (chosen; any emoji can be typed).
enum SpaceIconChoices {
    static let symbols = [
        "house", "briefcase", "book", "graduationcap", "hammer", "paintbrush", "music.note", "film", "gamecontroller", "cart",
        "airplane", "leaf", "flame", "bolt", "star", "heart", "globe", "terminal", "chevron.left.forwardslash.chevron.right",
        "camera", "cup.and.saucer", "dumbbell", "pawprint", "moon",
    ]
    static let emoji = ["🏠", "💼", "📚", "🎨", "🎵", "🎬", "🎮", "🛒", "✈️", "🌿", "🔥", "⚡️", "⭐️", "❤️", "🌍", "💻", "📷", "☕️",
                        "🏋️", "🐾", "🌙", "🧪", "🧭", "🍕"]
}

struct SpaceFormView: View {
    @Bindable var model: SpaceFormModel
    var onCommit: () -> Void
    var onCancel: () -> Void
    /// The wells or algorithm changed (the window previews the tint).
    var onThemeChange: () -> Void
    @FocusState private var focus: SpaceFormModel.Focus?
    @State private var addingProfile = false
    @State private var profileName = ""
    @State private var emojiField = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(model.title).font(.headline)
                TextField("Space Name", text: $model.name)
                    .textFieldStyle(.roundedBorder)
                    .focused($focus, equals: .name)
                    .onSubmit(onCommit)
                    .accessibilityIdentifier("space-form-name")
                iconSection
                themeSection
                profileSection
                HStack {
                    Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                    Spacer()
                    Button(model.commitTitle, action: onCommit)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("space-form-commit")
                }
            }
            .padding(.horizontal, SpaceFormMetrics.padding)
            .padding(.vertical, SpaceFormMetrics.padding)
        }
        .scrollIndicators(.never)
        .onExitCommand(perform: onCancel)
        .onAppear { focus = model.initialFocus }
        .onChange(of: model.themeColors) { onThemeChange() }
        .onChange(of: model.algorithm) { onThemeChange() }
        .onChange(of: model.opacity) { onThemeChange() }
    }

    // MARK: Icon

    private var iconSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Icon").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                TextField("Emoji", text: $emojiField)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 64)
                    .focused($focus, equals: .icon)
                    .onChange(of: emojiField) {
                        if let first = emojiField.first, first.unicodeScalars.first?.properties.isEmoji == true { model.icon = String(first) }
                    }
                Button("None") { model.icon = nil }.controlSize(.small)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(SpaceFormMetrics.iconCell), spacing: 4), count: 6), spacing: 4) {
                ForEach(SpaceIconChoices.symbols, id: \.self) { name in
                    iconButton(selected: model.icon == name) { Image(systemName: name) } action: { model.icon = name }
                }
                ForEach(SpaceIconChoices.emoji, id: \.self) { emoji in
                    iconButton(selected: model.icon == emoji) { Text(emoji) } action: { model.icon = emoji }
                }
            }
        }
    }

    private func iconButton(selected: Bool, @ViewBuilder label: () -> some View, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label()
                .frame(width: SpaceFormMetrics.iconCell, height: SpaceFormMetrics.iconCell)
                .background(selected ? Color.accentColor.opacity(SpaceFormMetrics.selectionAlpha) : .clear, in: .rect(cornerRadius: SpaceFormMetrics.cornerRadius))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: Theme

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Colour").font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(model.wells.indices, id: \.self) { index in
                    ColorPicker("", selection: Binding(get: { model.wells[index] }, set: { model.wells[index] = $0 }),
                                supportsOpacity: false)
                        .labelsHidden()
                        .contextMenu { Button("Remove Colour") { model.wells.remove(at: index) } }
                }
                if model.wells.count < ThemePalette.maxColors {
                    Button { model.addWell() } label: {
                        Image(systemName: "plus").frame(width: 28, height: 20)
                    }
                    .help("Click to add a color")
                    .accessibilityLabel("Click to add a color")
                }
                if !model.wells.isEmpty {
                    Button { model.wells.removeLast() } label: { Image(systemName: "minus").frame(width: 20, height: 20) }
                        .buttonStyle(.plain)
                        .help("Remove the last colour")
                }
            }
            .focused($focus, equals: .theme)
            Picker("Algorithm", selection: $model.algorithm) {
                Text("Complementary").tag(ThemeAlgorithm.complementary)
                Text("Split").tag(ThemeAlgorithm.split)
                Text("Analogous").tag(ThemeAlgorithm.analogous)
                Text("Triadic").tag(ThemeAlgorithm.triadic)
                Text("Floating").tag(ThemeAlgorithm.floating)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .accessibilityIdentifier("space-form-algorithm")
            TintOpacityControl(opacity: $model.opacity)
            // What the window tint will show.
            RoundedRectangle(cornerRadius: SpaceFormMetrics.cornerRadius)
                .fill(model.paletteColors.isEmpty
                      ? AnyShapeStyle(Color.secondary.opacity(SpaceFormMetrics.emptyPreviewAlpha))
                      : AnyShapeStyle(LinearGradient(colors: model.paletteColors.count == 1 ? [model.paletteColors[0], model.paletteColors[0].opacity(SpaceFormMetrics.previewFadeAlpha)]
                                                     : model.paletteColors, startPoint: .leading, endPoint: .trailing)))
                .frame(height: SpaceFormMetrics.previewHeight)
                .accessibilityLabel("Theme preview")
        }
    }

    // MARK: Profile

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Profile").font(.subheadline).foregroundStyle(.secondary)
            HStack {
                Picker("Profile", selection: $model.profileID) {
                    ForEach(model.profiles) { profile in Text(profile.name).tag(profile.id) }
                }
                .labelsHidden()
                .disabled(model.newProfileName != nil)
                Button("New…") { addingProfile = true }.controlSize(.small)
            }
            .help("Profiles are used to separate cookies and site data between spaces")
            if addingProfile || model.newProfileName != nil {
                HStack {
                    TextField("Profile Name", text: $profileName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { acceptProfile() }
                    Button(model.newProfileName == nil ? "Use" : "Undo") {
                        if model.newProfileName == nil { acceptProfile() } else { model.newProfileName = nil; profileName = ""; addingProfile = false }
                    }
                    .controlSize(.small)
                }
                if let name = model.newProfileName {
                    Text("A new profile “\(name)” is created with the space; logins and cookies won't carry over from other profiles.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func acceptProfile() {
        let trimmed = profileName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        model.newProfileName = trimmed
    }
}

/// The tint's opacity (B-23): 0–100 % of the space's `themeOpacity`, which the window maps into
/// `Materials.tintOpacityRange`. A view of its own so the space window (5.7b) takes it as it is.
public struct TintOpacityControl: View {
    @Binding var opacity: Double

    public init(opacity: Binding<Double>) {
        _opacity = opacity
    }

    public var body: some View {
        HStack(spacing: 8) {
            Text("Opacity").font(.subheadline).foregroundStyle(.secondary)
            Slider(value: $opacity, in: 0...1)
                .controlSize(.small)
                .accessibilityIdentifier("space-form-opacity")
            Text(opacity, format: .percent.precision(.fractionLength(0)))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 36, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tint opacity")
    }
}

/// Space form geometry (chosen; `docs/design-tokens.md`).

/// The form's hosting view: a list in the sidebar's list container.
final class SpaceFormHostingView: NSHostingView<SpaceFormView> {
    override var mouseDownCanMoveWindow: Bool { false }
}
