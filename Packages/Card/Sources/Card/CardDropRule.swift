/// Who takes content dropped on the card (5.5b, spec §I.7, ROADMAP 5.5
/// task 4): the page first, as in Chrome (a page's drop zones and fields
/// keep their drops; elsewhere Blink opens a dropped link or file in a new
/// tab), and Room for what the page refuses (text on a page that is not
/// editable becomes a search tab, image data a `file://` tab). Several links
/// are always Room's: Blink would open only the first.
public enum CardDropRule {
    public enum Owner: Equatable, Sendable {
        /// Forward the drop to the page's own view.
        case page
        /// Room opens tabs for it (`SidebarDrop.urls`).
        case room
        /// Nobody takes it.
        case none
    }

    /// - Parameters:
    ///   - links: `http`/`https` URLs on the pasteboard (as URLs, not text).
    ///   - files: file URLs on the pasteboard.
    ///   - fromPage: the drag began in a page (a link or image dragged inside
    ///     Room): the page's own business, as in Chrome (dropping a page's
    ///     link back on a page opens nothing).
    ///   - roomCanOpen: Room has tabs to open for it.
    ///   - pageAccepts: the page's last answer to the drag was an operation.
    public static func owner(links: Int, files: Int, fromPage: Bool, roomCanOpen: Bool, pageAccepts: Bool) -> Owner {
        if fromPage { return pageAccepts ? .page : .none }
        if links > 1, files == 0, roomCanOpen { return .room }
        if pageAccepts { return .page }
        return roomCanOpen ? .room : .none
    }
}
