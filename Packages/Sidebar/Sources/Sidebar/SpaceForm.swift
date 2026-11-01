import AppKit
import Combine
import Design
import Model
import SwiftUI

/// The space creation and edit form (spec §B): name ("Space Name"), icon
/// (emoji or SF Symbol), up to three colour wells with the five algorithms,
/// and the profile. A SwiftUI leaf in the space window (5.7b, B-122: a
/// window of its own, opened from Settings ▸ Spaces and the space's menu;
/// no editor inside the sidebar). Enter creates or saves, Esc cancels.
@Observable
public final class SpaceFormModel {
    public enum Mode: Equatable {
        case create
        case edit(UUID)
    }

    public typealias Focus = SpaceFormFocus

    public let mode: Mode
    public var name: String
    /// Emoji or SF Symbol name; `nil` = the default dot.
    public var icon: String?
    /// Up to three wells; the first is the base colour.
    public var wells: [Color]
    public var algorithm: ThemeAlgorithm
    public var opacity: Double
    public var profileID: UUID
    public var profiles: [Model.Profile]
    /// A profile the form will create on commit ("New Profile…").
    public var newProfileName: String?
    public var initialFocus: Focus
    /// The name used when the field is left empty.
    public let placeholderName: String

    public init(mode: Mode, space: Space?, profiles: [Model.Profile], defaultProfile: UUID, placeholderName: String, focus: Focus = .name) {
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

    /// The space this form edits (`nil` while it creates one).
    public var spaceID: UUID? {
        if case .edit(let id) = mode { return id }
        return nil
    }

    public var title: String { mode == .create ? "New Space" : "Edit Space" }
    public var commitTitle: String { mode == .create ? "Create" : "Save" }

    /// The wells as `#RRGGBB`.
    public var themeColors: [String] { wells.compactMap(Self.hex(of:)) }

    /// What the window tint will show: the wells extended by the algorithm.
    var paletteColors: [Color] { ThemePalette.colors(themeColors, algorithm: algorithm).compactMap(Self.color(hex:)) }

    /// The colour a new well starts with: the algorithm's next hue from the base, or a calm blue.
    public func addWell() {
        guard wells.count < ThemePalette.maxColors else { return }
        let derived = ThemePalette.colors(themeColors, algorithm: algorithm == .floating ? .triadic : algorithm)
        let next = derived.indices.contains(wells.count) ? derived[wells.count] : Palette.themeWellDefaultHex
        wells.append(Self.color(hex: next) ?? .blue)
    }

    public static func color(hex: String) -> Color? {
        guard let hsl = HSLColor(hex: hex) else { return nil }
        let (red, green, blue) = hsl.rgb
        return Color(.sRGB, red: red, green: green, blue: blue)
    }

    public static func hex(of color: Color) -> String? {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        return HSLColor(red: Double(rgb.redComponent), green: Double(rgb.greenComponent), blue: Double(rgb.blueComponent)).hex
    }
}

/// Which part of the space form has the focus when it opens (Change Icon…, Edit Theme…,
/// Space Routing Settings…: the routes, which the window scrolls to).
public enum SpaceFormFocus: Hashable, Sendable {
    case name, icon, theme, routes
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

/// The icon picker (spec §B; 5.6a: Change Icon… for entries and folders
/// takes it as it is): a field for any emoji, None, and the curated
/// symbols and emoji. `icon` is an emoji or an SF Symbol name, `nil` for none.
struct IconPickerView<Focus: Hashable>: View {
    @Binding var icon: String?
    var emojiFocus: FocusState<Focus?>.Binding
    var focusValue: Focus
    @State private var emojiField = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Icon").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                TextField("Emoji", text: $emojiField)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Icon emoji")
                    .accessibilityIdentifier("icon-picker-emoji")
                    .frame(width: 64)
                    .focused(emojiFocus, equals: focusValue)
                    .onChange(of: emojiField) {
                        if let first = emojiField.first, first.unicodeScalars.first?.properties.isEmoji == true { icon = String(first) }
                    }
                Button("None") { icon = nil }.controlSize(.small).accessibilityIdentifier("icon-picker-none")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(SpaceFormMetrics.iconCell), spacing: 4), count: 6), spacing: 4) {
                ForEach(SpaceIconChoices.symbols, id: \.self) { name in
                    iconButton(selected: icon == name) { Image(systemName: name) } action: { icon = name }
                        .accessibilityLabel(name)
                }
                ForEach(SpaceIconChoices.emoji, id: \.self) { emoji in
                    iconButton(selected: icon == emoji) { Text(emoji) } action: { icon = emoji }
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
}

/// Change Icon… for an entry or a folder (5.6a): the space form's picker in a
/// popover beside the row or tile. A choice applies at once and closes it;
/// None goes back to the favicon (a folder's glyph).
final class IconPopoverModel: ObservableObject {
    @Published var icon: String?
    init(icon: String?) { self.icon = icon }
}

struct IconPopoverView: View {
    @ObservedObject var model: IconPopoverModel
    @FocusState private var focus: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Change Icon").font(.headline)
            IconPickerView(icon: $model.icon, emojiFocus: $focus, focusValue: true)
        }
        .padding(SpaceFormMetrics.padding)
        .frame(width: SpaceFormMetrics.iconPopoverWidth)
    }
}

enum IconPopover {
    /// Shows the picker for `icon`; `onChange` gets each choice (the popover closes after it).
    @discardableResult
    static func show(icon: String?, relativeTo rect: NSRect, of view: NSView, onChange: @escaping (String?) -> Void) -> NSPopover {
        let model = IconPopoverModel(icon: icon)
        let controller = NSHostingController(rootView: IconPopoverView(model: model))
        controller.sizingOptions = [.preferredContentSize]
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = controller
        let observer = model.$icon.dropFirst().sink { [weak popover] value in
            onChange(value)
            popover?.performClose(nil)
        }
        objc_setAssociatedObject(popover, &observerKey, observer, .OBJC_ASSOCIATION_RETAIN)
        popover.show(relativeTo: rect, of: view, preferredEdge: .maxX)
        return popover
    }

    nonisolated(unsafe) private static var observerKey: UInt8 = 0
}

/// The form's body in the space window (5.11, the user on build 25: "think how Apple would design
/// that"): a grouped form, as System Settings' panes. A header with the space's icon as a tile washed
/// with its theme and the name beside it (a click on the tile opens the icon picker in a popover),
/// then Appearance, Profile and the window's `routes`; Cancel and Create/Save stay at the bottom.
public struct SpaceFormView: View {
    @Bindable var model: SpaceFormModel
    var routes: AnyView?
    var onCommit: () -> Void
    var onCancel: () -> Void
    /// The wells or algorithm changed (the window previews the tint).
    var onThemeChange: () -> Void
    @FocusState private var focus: SpaceFormModel.Focus?
    @State private var addingProfile = false
    @State private var profileName = ""
    @State private var pickingIcon = false

    public init(model: SpaceFormModel, routes: AnyView? = nil, onCommit: @escaping () -> Void, onCancel: @escaping () -> Void,
                onThemeChange: @escaping () -> Void) {
        self.model = model
        self.routes = routes
        self.onCommit = onCommit
        self.onCancel = onCancel
        self.onThemeChange = onThemeChange
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                Form {
                    Section { header }
                    themeSection
                    profileSection
                    // The routes' header row carries `SpaceFormFocus.routes` (a form scrolls to rows, not sections).
                    if let routes { routes }
                }
                .formStyle(.grouped)
                .onAppear {
                    switch model.initialFocus {
                    case .name: focus = .name
                    case .icon: pickingIcon = true
                    case .theme, .routes:
                        let target = model.initialFocus
                        DispatchQueue.main.async { proxy.scrollTo(target, anchor: .top) }
                    }
                }
            }
            Divider()
            HStack {
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Spacer()
                Button(model.commitTitle, action: onCommit)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("space-form-commit")
            }
            .padding(SpaceFormMetrics.padding)
        }
        .onExitCommand(perform: onCancel)
        .onChange(of: model.themeColors) { onThemeChange() }
        .onChange(of: model.algorithm) { onThemeChange() }
        .onChange(of: model.opacity) { onThemeChange() }
    }

    // MARK: Header: icon and name

    private var header: some View {
        HStack(spacing: 12) {
            Button { pickingIcon = true } label: { iconTile }
                .buttonStyle(.plain)
                .help("Choose an icon")
                .accessibilityLabel("Icon")
                .accessibilityIdentifier("space-form-icon")
                .popover(isPresented: $pickingIcon, arrowEdge: .bottom) {
                    IconPickerView(icon: $model.icon, emojiFocus: $focus, focusValue: .icon)
                        .padding(SpaceFormMetrics.padding)
                        .frame(width: SpaceFormMetrics.iconPopoverWidth)
                }
            TextField("Name", text: $model.name, prompt: Text(model.placeholderName))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .focused($focus, equals: .name)
                .onSubmit(onCommit)
                .accessibilityLabel("Space Name")
                .accessibilityIdentifier("space-form-name")
        }
        .padding(.vertical, 4)
    }

    /// The space's icon on its theme's wash (the dot without an icon).
    private var iconTile: some View {
        let colors = model.paletteColors
        return RoundedRectangle(cornerRadius: SpaceFormMetrics.headerTileCorner, style: .continuous)
            .fill(colors.isEmpty
                  ? AnyShapeStyle(Color.secondary.opacity(SpaceFormMetrics.emptyPreviewAlpha))
                  : AnyShapeStyle(LinearGradient(colors: (colors.count == 1 ? [colors[0], colors[0]] : colors)
                                                    .map { $0.opacity(SpaceFormMetrics.headerWashAlpha) },
                                                 startPoint: .topLeading, endPoint: .bottomTrailing)))
            .frame(width: SpaceFormMetrics.headerIcon, height: SpaceFormMetrics.headerIcon)
            .overlay {
                Group {
                    if let icon = model.icon, !icon.isEmpty {
                        if icon.unicodeScalars.first?.properties.isEmoji == true, NSImage(systemSymbolName: icon, accessibilityDescription: nil) == nil {
                            Text(icon).font(.system(size: SpaceFormMetrics.headerGlyph))
                        } else {
                            Image(systemName: icon).font(.system(size: SpaceFormMetrics.headerGlyph, weight: .medium))
                        }
                    } else {
                        Circle().frame(width: SpaceFormMetrics.headerGlyph / 2, height: SpaceFormMetrics.headerGlyph / 2)
                    }
                }
                .foregroundStyle(.primary)
            }
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "pencil.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.accentColor)
                    .font(.system(size: 16))
                    .offset(x: 4, y: 4)
            }
    }

    // MARK: Theme

    private var themeSection: some View {
        Section("Appearance") {
            LabeledContent("Colours") {
                HStack(spacing: 8) {
                    ForEach(model.wells.indices, id: \.self) { index in
                        // Guarded: a well removed (−, Remove Colour, a reset) can be read once more by the old binding.
                        ColorPicker("", selection: Binding(get: { model.wells.indices.contains(index) ? model.wells[index] : .clear },
                                                           set: { if model.wells.indices.contains(index) { model.wells[index] = $0 } }),
                                    supportsOpacity: false)
                            .labelsHidden()
                            .accessibilityLabel("Colour \(index + 1)")
                            .contextMenu { Button("Remove Colour") { if model.wells.indices.contains(index) { model.wells.remove(at: index) } } }
                    }
                    if !model.wells.isEmpty {
                        Button { model.wells.removeLast() } label: { Image(systemName: "minus") }
                            .buttonStyle(.borderless)
                            .help("Remove the last colour")
                            .accessibilityLabel("Remove the last colour")
                    }
                    if model.wells.count < ThemePalette.maxColors {
                        Button { model.addWell() } label: { Image(systemName: "plus") }
                            .buttonStyle(.borderless)
                            .help("Click to add a color")
                            .accessibilityLabel("Click to add a color")
                    }
                }
            }
            .focused($focus, equals: .theme)
            .id(SpaceFormFocus.theme)
            Picker("Harmony", selection: $model.algorithm) {
                Text("Complementary").tag(ThemeAlgorithm.complementary)
                Text("Split").tag(ThemeAlgorithm.split)
                Text("Analogous").tag(ThemeAlgorithm.analogous)
                Text("Triadic").tag(ThemeAlgorithm.triadic)
                Text("Floating").tag(ThemeAlgorithm.floating)
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("space-form-algorithm")
            TintOpacityControl(opacity: $model.opacity)
            // What the window tint will show.
            RoundedRectangle(cornerRadius: SpaceFormMetrics.cornerRadius)
                .fill(model.paletteColors.isEmpty
                      ? AnyShapeStyle(Color.secondary.opacity(SpaceFormMetrics.emptyPreviewAlpha))
                      : AnyShapeStyle(LinearGradient(colors: model.paletteColors.count == 1 ? [model.paletteColors[0], model.paletteColors[0].opacity(SpaceFormMetrics.previewFadeAlpha)]
                                                     : model.paletteColors, startPoint: .leading, endPoint: .trailing)))
                .frame(height: SpaceFormMetrics.previewHeight)
                // An image to VoiceOver (5.3a: a shape alone had no role).
                .accessibilityElement()
                .accessibilityAddTraits(.isImage)
                .accessibilityLabel("Theme preview")
        }
    }

    // MARK: Profile

    private var profileSection: some View {
        Section {
            Picker("Profile", selection: $model.profileID) {
                ForEach(model.profiles) { profile in Text(profile.name).tag(profile.id) }
            }
            .disabled(model.newProfileName != nil)
            if addingProfile || model.newProfileName != nil {
                LabeledContent("New Profile") {
                    HStack {
                        TextField("Profile Name", text: $profileName)
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { acceptProfile() }
                        Button(model.newProfileName == nil ? "Use" : "Undo") {
                            if model.newProfileName == nil { acceptProfile() } else { model.newProfileName = nil; profileName = ""; addingProfile = false }
                        }
                    }
                }
            } else {
                HStack {
                    Spacer()
                    Button("New Profile…") { addingProfile = true }
                }
            }
        } header: {
            Text("Profile")
        } footer: {
            Text(model.newProfileName.map { "A new profile “\($0)” is created with the space; logins and cookies won't carry over from other profiles." }
                 ?? "Profiles keep cookies, logins and site data apart between spaces.")
                .font(.caption).foregroundStyle(.secondary)
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
        LabeledContent("Opacity") {
            HStack(spacing: 8) {
                Slider(value: $opacity, in: 0...1)
                    .controlSize(.small)
                    .accessibilityIdentifier("space-form-opacity")
                Text(opacity, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 36, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tint opacity")
    }
}


