#if DEBUG
import AppKit
import Design
import Model
import Sidebar
import UIKitCore

/// 5.7b (B-122): `-RoomSpike spacewindow`. The space window opened from
/// Settings ▸ Spaces (Edit…) and from the space's menu in the sidebar (Space
/// Settings…, Change Icon…, Edit Theme…, Space Routing Settings…, New
/// Space), its name, icon, theme, profile and routes edited through its
/// models and saved, the state read back from the store; Cancel and the
/// close button write nothing; a new space from the window; the sidebar
/// holds no form (its list views counted before and after).
extension SpikeRunner.Context {
    func spaceWindowChecks() async {
        guard let app = AppDelegate.current, let first = store.spaces.first else { return SpikeRunner.record("error", "spacewindow: no state") }
        window.setContentSize(NSSize(width: 1200, height: 780))
        await activate()
        try? await Task.sleep(for: .milliseconds(600))
        let listViews = { self.sidebar.bodyView.debugListViews.count }
        let listsBefore = listViews()
        func describe(_ id: UUID) -> String {
            guard let space = store.space(id) else { return "missing" }
            let profile = store.profiles.first { $0.id == space.profileID }?.name ?? "?"
            let rules = store.routingRules.filter { $0.targetSpaceID == id }
                .map { "\($0.match.rawValue):\($0.pattern):\($0.enabled ? "on" : "off")" }
            return "name=\(space.name) icon=\(space.icon ?? "nil") colours=\(space.themeColors) algorithm=\(space.themeAlgorithm.rawValue) "
                + String(format: "opacity=%.2f ", space.themeOpacity) + "profile=\(profile) routes=\(rules)"
        }
        func windowState() -> String {
            guard let controller = app.spaceWindow, let target = controller.window else { return "absent" }
            let visible = (target.screen ?? NSScreen.main)?.visibleFrame ?? .zero
            return "shown=\(target.isVisible) key=\(target.isKeyWindow) title=\"\(target.title)\" space=\(controller.model.spaceID.flatMap { store.space($0)?.name } ?? "new") "
                + "focus=\(controller.model.initialFocus) inside visible frame=\(visible.contains(target.frame)) size=\(NSStringFromSize(target.frame.size))"
        }
        SpikeRunner.record("space_before", describe(first.id))

        // 1. Settings ▸ Spaces ▸ the space's Edit….
        app.showSettings(section: .spaces)
        try? await Task.sleep(for: .milliseconds(600))
        app.debugSettingsWindow?.services.profiles.editSpace(first.id)
        _ = await waitUntil(3) { app.spaceWindow?.window?.isVisible == true }
        SpikeRunner.record("from_settings", windowState())
        guard let controller = app.spaceWindow else { return SpikeRunner.record("error", "spacewindow: no window from Settings") }
        // Name, icon, theme and a new profile, as the form's controls write them; the tint previews.
        let model = controller.model
        var tints: [String] = []
        let tintBefore = sidebar.onTintChange
        sidebar.onTintChange = { theme, animated in
            tints.append(theme.map { "\($0.colors.count) colours" } ?? "neutral")
            tintBefore?(theme, animated)
        }
        model.name = "Garden"
        model.icon = "leaf"
        model.wells = [SpaceFormModel.color(hex: "#3E9B5B")!]
        model.algorithm = .triadic
        model.opacity = 0.8
        model.newProfileName = "Outdoors"
        sidebar.previewTheme(model)
        // Routes: two added in the window, one switched off, a bad regex refused.
        if let routes = controller.routes {
            routes.match = .contains
            routes.pattern = "garden.example"
            let first = routes.add()
            routes.match = .equals
            routes.pattern = "plants.test"
            let second = routes.add()
            routes.match = .regex
            routes.pattern = "([a-z"
            let refused = !routes.add() && routes.patternError != nil
            routes.pattern = ""
            if let rule = routes.rules.last { routes.setEnabled(rule.id, false) }
            SpikeRunner.record("routes_edit", "added=\(first && second) bad regex refused=\(refused) listed=\(routes.rules.count)")
        } else {
            SpikeRunner.record("routes_edit", "no routes section")
        }
        try? await Task.sleep(for: .milliseconds(300))
        await spaceWindowCapture(controller.window, "edit")
        let saved = controller.commit()
        _ = await waitUntil(2) { app.spaceWindow == nil }
        try? await Task.sleep(for: .milliseconds(300))
        SpikeRunner.record("saved", "window gone=\(app.spaceWindow == nil) id=\(saved == first.id) " + describe(first.id))
        SpikeRunner.record("tint", "preview and saved: \(tints.joined(separator: ", ")); window title=\(window.title)")
        app.debugSettingsWindow?.window?.orderOut(nil)
        window.makeKeyAndOrderFront(nil)

        // 2. The space's menu in the sidebar: each item opens the window at its part.
        guard let menu = sidebar.debugSpaceMenu(first.id) else { return SpikeRunner.record("error", "spacewindow: no space menu") }
        SpikeRunner.record("space_menu", menu.items.filter { !$0.isSeparatorItem }.map { "\($0.title)\($0.isEnabled ? "" : " (off)")" }.joined(separator: " | "))
        for title in [SpaceCommandName.spaceSettings, SpaceCommandName.changeIcon, SpaceCommandName.editTheme, SpaceCommandName.routingSettings] {
            guard let menu = sidebar.debugSpaceMenu(first.id), let index = menu.items.firstIndex(where: { $0.title == title }) else {
                SpikeRunner.record("menu_\(title)", "missing")
                continue
            }
            menu.performActionForItem(at: index)
            _ = await waitUntil(3) { app.spaceWindow?.window?.isVisible == true }
            try? await Task.sleep(for: .milliseconds(300))
            SpikeRunner.record("menu_item", "\(title) → \(windowState())")
            if title == SpaceCommandName.routingSettings { await spaceWindowCapture(app.spaceWindow?.window, "routes") }
            app.spaceWindow?.cancel()
            _ = await waitUntil(2) { app.spaceWindow == nil }
        }

        // 3. Cancel and the close button write nothing; the tint goes back.
        let unchanged = describe(first.id)
        app.showSpaceWindow(first.id, focus: .name, from: sidebar)
        _ = await waitUntil(3) { app.spaceWindow != nil }
        app.spaceWindow?.model.name = "Not Saved"
        app.spaceWindow?.model.wells = []
        if let model = app.spaceWindow?.model { sidebar.previewTheme(model) }
        app.spaceWindow?.cancel()
        _ = await waitUntil(2) { app.spaceWindow == nil }
        let afterCancel = describe(first.id)
        app.showSpaceWindow(first.id, focus: .name, from: sidebar)
        _ = await waitUntil(3) { app.spaceWindow != nil }
        app.spaceWindow?.model.name = "Not Saved Either"
        app.spaceWindow?.window?.performClose(nil)
        _ = await waitUntil(2) { app.spaceWindow == nil }
        SpikeRunner.record("cancel", "cancel unchanged=\(afterCancel == unchanged) close button unchanged=\(describe(first.id) == unchanged) "
            + "window gone=\(app.spaceWindow == nil) last tint=\(tints.last ?? "none")")

        // 4. New Space ("+" ▸ New Space's action): the window creates and the sidebar shows the space.
        let count = store.spaces.count
        NSApp.sendAction(#selector(AppDelegate.newSpace(_:)), to: nil, from: nil)
        _ = await waitUntil(3) { app.spaceWindow?.window?.isVisible == true }
        SpikeRunner.record("new_space_window", windowState() + " routes section=\(app.spaceWindow?.routes == nil ? "placeholder" : "present")")
        await spaceWindowCapture(app.spaceWindow?.window, "new")
        app.spaceWindow?.model.name = "Studio"
        app.spaceWindow?.model.icon = "🎨"
        let created = app.spaceWindow?.commit()
        _ = await waitUntil(2) { app.spaceWindow == nil }
        try? await Task.sleep(for: .milliseconds(800))
        SpikeRunner.record("new_space", "spaces \(count) → \(store.spaces.count) shown=\(sidebar.activeSpace?.name ?? "nil") "
            + "created=\(created.map(describe) ?? "nil")")

        // 5. No editor in the sidebar: its list container holds the spaces' lists only.
        SpikeRunner.record("sidebar_lists", "before=\(listsBefore) after=\(listViews()) spaces=\(store.spaces.count) "
            + "form views=\(sidebar.bodyView.debugListViews.filter { NSStringFromClass(Swift.type(of: $0)).contains("SpaceForm") }.count)")
        sidebar.onTintChange = tintBefore
    }

    private func spaceWindowCapture(_ target: NSWindow?, _ name: String) async {
        guard let target, let directory = UserDefaults.standard.string(forKey: "RoomSpikeCaptureDirectory") else { return }
        target.displayIfNeeded()
        try? await Task.sleep(for: .milliseconds(200))
        let url = URL(fileURLWithPath: directory).appending(path: "spacewindow-\(name).png")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        SpikeRunner.record("capture_\(name)", (try? WindowSnapshot.writePNG(target, to: url)) != nil ? url.lastPathComponent : "failed")
    }
}
#endif
