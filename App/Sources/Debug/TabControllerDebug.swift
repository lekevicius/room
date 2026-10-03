#if DEBUG
import Engine
import FakeEngine
import Foundation
import Tabs

/// Hooks for the DEBUG sidebar snapshot runner, which runs the tab
/// controller on FakeEngine pages (what Phase 2.2's `SidebarPages` offered).
extension TabController {
    /// Loads an entry's page without showing it; `stalled` leaves it loading.
    func debugLoad(_ id: UUID, stalled: Bool = false) {
        guard contents(for: id) == nil, let entry = store.sidebar.entry(id), let page = loadInBackground(entry) else { return }
        if stalled, let fake = page as? FakeWebContents {
            fake.loadsSynchronously = false
            fake.reload()
        }
    }

    /// A same-site link click in the selected page (makes a pinned entry "changed").
    func debugNavigateSelected() {
        guard let page = current as? FakeWebContents, let url = page.url else { return }
        page.simulateLinkClick(to: url.appending(path: "page-\(Int.random(in: 1...999))"))
    }
}
#endif
