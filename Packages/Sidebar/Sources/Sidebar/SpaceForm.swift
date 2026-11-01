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

/// The icon picker's symbols (5.12: some 200, filled, from the everyday to the specific).
enum SpaceIconChoices {
    static let symbols = [
        "star.fill", "bookmark.fill", "heart.fill", "flag.fill", "bolt.fill", "triangle.fill", "asterisk", "bell.fill",
        "lightbulb.fill", "square.on.circle.fill", "square.grid.2x2.fill", "circle.grid.3x3.fill", "square.stack.3d.up.fill",
        "cylinder.split.1x2.fill", "tray.full.fill", "square.on.square.fill", "folder.fill", "tray.fill", "calendar",
        "envelope.fill", "checkmark.square.fill", "doc.fill", "book.fill", "bubble.left.fill", "person.2.fill",
        "apple.terminal.fill", "hammer.fill", "wrench.and.screwdriver.fill", "square.fill", "drop.fill", "circle.fill",
        "moon.fill", "sun.max.fill", "globe.americas.fill", "leaf.fill", "cloud.fill", "pawprint.fill", "basket.fill",
        "gift.fill", "bed.double.fill", "fork.knife", "dumbbell.fill", "airplane", "music.note", "paintpalette.fill",
        "video.fill", "bandage.fill", "chevron.left.forwardslash.chevron.right", "baseball.fill", "map.fill", "flame.fill",
        "house.fill", "building.2.fill", "briefcase.fill", "graduationcap.fill", "cart.fill", "bag.fill", "creditcard.fill",
        "banknote.fill", "chart.bar.fill", "chart.pie.fill", "gamecontroller.fill", "film.fill", "tv.fill", "headphones",
        "camera.fill", "photo.fill", "mic.fill", "phone.fill", "message.fill", "paperplane.fill", "link", "globe",
        "magnifyingglass", "lock.fill", "key.fill", "shield.fill", "gearshape.fill", "cpu.fill", "desktopcomputer",
        "laptopcomputer", "iphone", "keyboard.fill", "printer.fill", "server.rack", "externaldrive.fill", "wifi",
        "antenna.radiowaves.left.and.right", "car.fill", "bus.fill", "tram.fill", "bicycle", "sailboat.fill", "fuelpump.fill",
        "location.fill", "mappin", "mountain.2.fill", "tree.fill", "tortoise.fill", "hare.fill", "bird.fill", "fish.fill",
        "ant.fill", "ladybug.fill", "carrot.fill", "cup.and.saucer.fill", "wineglass.fill", "birthday.cake.fill",
        "popcorn.fill", "sportscourt.fill", "soccerball", "basketball.fill", "tennisball.fill", "figure.run", "figure.hiking",
        "figure.yoga", "trophy.fill", "medal.fill", "crown.fill", "sparkles", "wand.and.stars", "theatermasks.fill",
        "puzzlepiece.fill", "dice.fill", "guitars.fill", "pianokeys", "pencil.and.ruler.fill", "scissors", "paintbrush.fill",
        "eyedropper.full", "ruler.fill", "compass.drawing", "atom", "flask.fill", "testtube.2", "brain.head.profile",
        "stethoscope", "cross.case.fill", "pills.fill", "heart.text.square.fill", "newspaper.fill", "books.vertical.fill",
        "text.book.closed.fill", "note.text", "list.bullet", "checklist", "clock.fill", "alarm.fill", "hourglass", "timer",
        "stopwatch.fill", "bell.badge.fill", "tag.fill", "pin.fill", "paperclip", "archivebox.fill", "shippingbox.fill",
        "cube.fill", "hexagon.fill", "seal.fill", "burst.fill", "snowflake", "umbrella.fill", "thermometer.medium", "tornado",
        "hurricane", "rainbow", "sunrise.fill", "moon.stars.fill", "sparkle", "eye.fill", "hand.thumbsup.fill",
        "hand.raised.fill", "face.smiling.inverse", "person.fill", "person.3.fill", "figure.2.and.child.holdinghands",
        "dog.fill", "cat.fill", "lizard.fill", "teddybear.fill", "balloon.fill", "party.popper.fill", "tent.fill",
        "beach.umbrella.fill", "house.lodge.fill", "storefront.fill", "building.columns.fill", "dollarsign.circle.fill",
        "eurosign.circle.fill", "bitcoinsign.circle.fill", "bolt.heart.fill", "infinity", "number", "questionmark.circle.fill",
        "exclamationmark.triangle.fill", "xmark.octagon.fill", "checkmark.seal.fill",
    ]

    /// Emoji whose name has every word of `query`, by group (`EmojiCatalog`); all of them for an empty query.
    static func emoji(matching query: String) -> [(group: EmojiCatalog.Group, emoji: [String])] {
        let words = query.lowercased().split(separator: " ")
        return EmojiCatalog.groups.compactMap { group in
            var found: [String] = []
            var index = 0
            while index + 1 < group.items.count {
                let name = group.items[index + 1].lowercased()
                if words.allSatisfy({ name.contains($0) }) { found.append(group.items[index]) }
                index += 2
            }
            return found.isEmpty ? nil : (group, found)
        }
    }

    /// Symbols whose name has `query` (dots read as spaces: "cup" finds cup.and.saucer.fill).
    static func symbols(matching query: String) -> [String] {
        let words = query.lowercased().split(separator: " ")
        guard !words.isEmpty else { return symbols }
        return symbols.filter { name in
            let spaced = name.replacingOccurrences(of: ".", with: " ")
            return words.allSatisfy { spaced.contains($0) }
        }
    }
}

/// The icon picker (spec §B; 5.6a: Change Icon… for entries and folders takes it as it is; 5.12:
/// every emoji and some 200 symbols, the user on build 26). Emoji or Icon, a search field, the grid
/// (emoji under their group's name) and, for emoji, a bar that jumps to each group; the bin clears
/// the icon. `icon` is an emoji or an SF Symbol name, `nil` for none.
struct IconPickerView<Focus: Hashable>: View {
    enum Kind: String, CaseIterable { case emoji = "Emoji", icon = "Icon" }

    @Binding var icon: String?
    var emojiFocus: FocusState<Focus?>.Binding
    var focusValue: Focus
    @State private var kind: Kind
    @State private var query = ""

    init(icon: Binding<String?>, emojiFocus: FocusState<Focus?>.Binding, focusValue: Focus) {
        _icon = icon
        self.emojiFocus = emojiFocus
        self.focusValue = focusValue
        // Opens on the kind of the icon it has (a symbol name has a letter where an emoji has none).
        let isSymbol = icon.wrappedValue.map { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil } ?? false
        _kind = State(initialValue: isSymbol ? .icon : .emoji)
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.fixed(SpaceFormMetrics.pickerCell), spacing: 0), count: SpaceFormMetrics.pickerColumns)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Picker("Icon kind", selection: $kind) {
                    ForEach(Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityIdentifier("icon-picker-kind")
                Button { icon = nil } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .help("No icon")
                    .accessibilityLabel("No icon")
                    .accessibilityIdentifier("icon-picker-none")
            }
            TextField("Search", text: $query, prompt: Text(kind == .emoji ? "Search emoji" : "Search symbols"))
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("icon-picker-search")
                .focused(emojiFocus, equals: focusValue)
                .onSubmit(pickFirst)
            switch kind {
            case .emoji: emojiGrid
            case .icon: symbolGrid
            }
        }
        .onChange(of: kind) { query = "" }
        // An emoji typed or pasted (or from ⌃⌘Space's palette) is the icon, as the old field's was.
        .onChange(of: query) {
            if let first = query.first, first.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation }) {
                icon = String(first)
                query = ""
            }
        }
    }

    private var emojiGrid: some View {
        let groups = SpaceIconChoices.emoji(matching: query)
        return ScrollViewReader { proxy in
            VStack(spacing: 4) {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(groups, id: \.group.id) { entry in
                            Section {
                                ForEach(entry.emoji, id: \.self) { emoji in
                                    cell(selected: icon == emoji) { Text(emoji).font(.system(size: SpaceFormMetrics.pickerGlyph)) } action: { icon = emoji }
                                }
                            } header: {
                                Text(entry.group.name)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 4)
                                    .background(.regularMaterial)
                                    .id(entry.group.id)
                            }
                        }
                    }
                }
                .frame(height: SpaceFormMetrics.pickerGridHeight)
                .overlay { if groups.isEmpty { Text("No Emoji").foregroundStyle(.secondary) } }
                if query.isEmpty {
                    Divider()
                    HStack(spacing: 0) {
                        ForEach(EmojiCatalog.groups) { group in
                            Button { withAnimation { proxy.scrollTo(group.id, anchor: .top) } } label: {
                                Image(systemName: group.symbol)
                                    .frame(maxWidth: .infinity, minHeight: SpaceFormMetrics.pickerCell * 0.75)
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help(group.name)
                            .accessibilityLabel(group.name)
                        }
                    }
                }
            }
        }
    }

    private var symbolGrid: some View {
        let names = SpaceIconChoices.symbols(matching: query)
        return ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 0) {
                ForEach(names, id: \.self) { name in
                    cell(selected: icon == name) { Image(systemName: name).font(.system(size: SpaceFormMetrics.pickerSymbol)) } action: { icon = name }
                        .accessibilityLabel(name)
                        .help(name)
                }
            }
        }
        .frame(height: SpaceFormMetrics.pickerGridHeight)
        .overlay { if names.isEmpty { Text("No Symbols").foregroundStyle(.secondary) } }
    }

    /// Return picks the first match.
    private func pickFirst() {
        switch kind {
        case .emoji: if let first = SpaceIconChoices.emoji(matching: query).first?.emoji.first { icon = first }
        case .icon: if let first = SpaceIconChoices.symbols(matching: query).first { icon = first }
        }
    }

    private func cell(selected: Bool, @ViewBuilder label: () -> some View, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label()
                .frame(width: SpaceFormMetrics.pickerCell, height: SpaceFormMetrics.pickerCell)
                .background(selected ? Color.accentColor.opacity(SpaceFormMetrics.selectionAlpha) : .clear, in: .rect(cornerRadius: SpaceFormMetrics.cornerRadius))
                .contentShape(.rect)
        }
        .buttonStyle(IconCellStyle())
    }
}

/// The picker's cells: the rows' hover fill under the pointer.
private struct IconCellStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { IconCell(configuration: configuration) }

    private struct IconCell: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false
        var body: some View {
            configuration.label
                .foregroundStyle(.primary)
                .background(hovering || configuration.isPressed ? Color(nsColor: Palette.sidebarHover) : .clear,
                            in: .rect(cornerRadius: SpaceFormMetrics.cornerRadius))
                .onHover { hovering = $0 }
        }
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
                    .font(.system(size: SpaceFormMetrics.headerBadge))
                    .offset(x: SpaceFormMetrics.headerBadge / 4, y: SpaceFormMetrics.headerBadge / 4)
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


