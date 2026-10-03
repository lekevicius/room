import AppKit
import Design
import Engine
import SwiftUI
import UniformTypeIdentifiers

/// The popover's content: the list, newest first, and Clear.
final class DownloadsViewController: NSHostingController<DownloadsListView> {
    init(list: DownloadList) {
        super.init(rootView: DownloadsListView(list: list))
        sizingOptions = [.preferredContentSize]
    }

    @available(*, unavailable)
    @MainActor required dynamic init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

struct DownloadsListView: View {
    let list: DownloadList

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Downloads").font(.headline)
                Spacer()
                Button("Clear") { list.clear() }
                    .buttonStyle(.link)
                    .disabled(!list.canClear)
                    .accessibilityIdentifier("downloads-clear")
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)
            if list.rows.isEmpty {
                Text("No downloads")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 64)
            } else {
                let showProfile = Set(list.rows.map(\.profileName)).count > 1
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(list.rows) { row in
                            DownloadRowView(row: row, showProfile: showProfile, list: list)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 8)
                }
                .frame(height: min(CGFloat(list.rows.count), CGFloat(DownloadsMetrics.maxVisibleRows)) * 52 + 8)
            }
        }
        .frame(width: DownloadsMetrics.popoverWidth)
    }
}

struct DownloadRowView: View {
    let row: DownloadList.Row
    let showProfile: Bool
    let list: DownloadList
    @State private var hovering = false

    private var item: DownloadItem { row.item }
    private var name: String { (row.item.destination ?? row.destination)?.lastPathComponent ?? item.suggestedFilename }

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: DownloadsMetrics.rowIconSize, height: DownloadsMetrics.rowIconSize)
                .opacity(item.state == .complete ? 1 : 0.6)
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(Font(Typography.row))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if item.state == .inProgress {
                    if let fraction = item.fractionCompleted {
                        ProgressView(value: fraction).progressViewStyle(.linear).controlSize(.small)
                    } else {
                        ProgressView().progressViewStyle(.linear).controlSize(.small)
                    }
                }
                Text(DownloadRules.detail(for: item) + (showProfile ? " · \(row.profileName)" : ""))
                    .font(Font(Typography.secondary))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            trailing
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
            .fill(hovering ? Color(nsColor: Palette.sidebarHover) : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { list.open(row.id) }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("download-row")
    }

    @ViewBuilder private var trailing: some View {
        switch item.state {
        case .inProgress:
            iconButton(.cancel, help: "Cancel") { list.cancel(row.id) }
                .accessibilityIdentifier("download-cancel")
        case .interrupted where item.canResume:
            iconButton(.reload, help: "Resume") { list.resume(row.id) }
        case .complete:
            iconButton(.showInFinder, help: "Show in Finder") { list.reveal(row.id) }
                .opacity(hovering ? 1 : 0)
                .accessibilityIdentifier("download-reveal")
        default:
            EmptyView()
        }
    }

    private func iconButton(_ symbol: Symbol, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol.name).foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var icon: NSImage {
        if item.state == .complete, let url = item.destination ?? row.destination, FileManager.default.fileExists(atPath: url.path) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        let ext = (name as NSString).pathExtension
        return NSWorkspace.shared.icon(for: UTType(filenameExtension: ext) ?? .data)
    }
}
