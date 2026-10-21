#if DEBUG
import AppKit
import Engine

/// `branding` (5.2b, B-103; `scripts/branding-check.sh`): no visible Chromium name or icon in Room.
/// Opens each of Chrome's own pages Room shows (Settings and its About, History, Downloads,
/// Extensions, the password manager, print preview, Version, Bookmarks) as a tab on a throwaway
/// state and reads from the page: every text node and label across its shadow roots, and every
/// string the page was given (`loadTimeData`), for "Chromium"; its logo images' mean colour (Chromium's
/// is blue, Room's glyph peach and violet). Then the notification icon: the alerts helper's bundle
/// icon beside Room's own. Lines for spike-results and the review sheet's captures
/// (`-RoomSpikeSheetDirectory`). The attribution line ("made possible by the Chromium open source
/// project") is expected and counted apart.
extension SpikeRunner.Context {
    static let brandingPages: [(String, String)] = [
        ("settings", "chrome://settings"), ("about", "chrome://settings/help"), ("privacy", "chrome://settings/privacy"),
        ("defaultbrowser", "chrome://settings/defaultBrowser"), ("autofill", "chrome://settings/autofill"),
        ("history", "chrome://history"), ("downloads", "chrome://downloads"), ("extensions", "chrome://extensions"),
        ("passwords", "chrome://password-manager"), ("print", "chrome://print"), ("version", "chrome://version"),
        ("bookmarks", "chrome://bookmarks"),
    ]

    /// The page's text, labels and strings with "Chromium", and its logos' colours (JSON).
    static let brandingProbe = """
    (async () => {
      const texts = [], seen = new Set();
      const walk = (root) => {
        const nodes = root.querySelectorAll('*');
        for (const node of nodes) {
          for (const attribute of ['title', 'aria-label', 'placeholder', 'alt', 'aria-description']) {
            const value = node.getAttribute && node.getAttribute(attribute);
            if (value) texts.push(value);
          }
          if (node.shadowRoot) walk(node.shadowRoot);
        }
        const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
        while (walker.nextNode()) {
          const t = walker.currentNode.nodeValue.trim();
          if (!t) continue;
          // A linked name ("the <a>Chromium</a> open source project") is read with its sentence.
          const around = walker.currentNode.parentElement?.closest('a')?.parentElement?.textContent?.trim();
          texts.push(around && /Chromium/.test(t) ? around : t);
        }
      };
      walk(document);
      texts.push(document.title);
      const attribution = /Chromium open source project|The Chromium Authors/;
      const hits = texts.filter(t => /Chromium/.test(t));
      const visible = hits.filter(t => !attribution.test(t) || /Chromium/.test(t.replace(attribution, '')));
      const strings = [];
      try {
        const data = (window.loadTimeData && loadTimeData.data_) || {};
        for (const [key, value] of Object.entries(data)) {
          if (typeof value === 'string' && /Chromium/.test(value) && !attribution.test(value)) strings.push(key + '=' + value.slice(0, 80));
        }
      } catch (e) {}
      const logos = [];
      const images = [];
      const collect = (root) => {
        for (const node of root.querySelectorAll('img, cr-icon, iron-icon')) images.push(node);
        for (const node of root.querySelectorAll('*')) if (node.shadowRoot) collect(node.shadowRoot);
      };
      collect(document);
      for (const img of images) {
        const src = img.currentSrc || img.src || '';
        if (/theme|logo|product/i.test(src + ' ' + (img.id || '') + ' ' + (img.className || ''))) logos.push(src);
      }
      return JSON.stringify({ text: hits.length, visible: visible.length, examples: visible.slice(0, 4).map(t => t.slice(0, 90)),
                              attribution: hits.length - visible.length, strings: strings.length, stringExamples: strings.slice(0, 4), logos });
    })()
    """

    func brandingChecks() async {
        let only = Set((UserDefaults.standard.string(forKey: "RoomSpikeOnly") ?? "").split(separator: ",").map(String.init))
        let sheets = UserDefaults.standard.string(forKey: "RoomSpikeSheetDirectory").map { URL(fileURLWithPath: $0) }
        window.setContentSize(NSSize(width: 1200, height: 780))
        var total = 0, strings = 0
        var logoURLs = Set<String>()
        var rows: [SheetRow] = []
        for (name, address) in Self.brandingPages where only.isEmpty || only.contains(name) {
            guard let url = URL(string: address), let page = await open(url, timeout: 20) else {
                SpikeRunner.record("branding_\(name)", "error: did not open")
                continue
            }
            try? await Task.sleep(for: .seconds(2))
            let json = await js(page, Self.brandingProbe)
            let result = (try? JSONSerialization.jsonObject(with: Data(json.utf8), options: .fragmentsAllowed)) as? String
            let fields = result.flatMap { (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any] }
            if let fields {
                let visible = fields["visible"] as? Int ?? -1, inStrings = fields["strings"] as? Int ?? -1
                total += max(visible, 0)
                strings += max(inStrings, 0)
                SpikeRunner.record("branding_\(name)", "url=\(page.url?.absoluteString ?? "-") visible_chromium=\(visible) "
                    + "attribution=\(fields["attribution"] ?? "?") strings_chromium=\(inStrings) "
                    + "examples=\((fields["examples"] as? [String] ?? []).joined(separator: " ¦ ")) "
                    + "string_examples=\((fields["stringExamples"] as? [String] ?? []).joined(separator: " ¦ "))")
                let logos = fields["logos"] as? [String] ?? []
                SpikeRunner.record("branding_\(name)_logos", logos.joined(separator: "; ").ifEmpty("none"))
                logoURLs.formUnion(logos)
            } else {
                SpikeRunner.record("branding_\(name)", "error: probe \(json.prefix(160))")
            }
            if sheets != nil {
                // The page's own pixels (a window capture shows the card without the engine's layer).
                let shot = await PageDriver.capture(page, "branding \(name)").flatMap { image -> CGImage? in
                    guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
                    let size = CGSize(width: CGFloat(cg.width) / 2, height: CGFloat(cg.height) / 2)
                    guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return cg }
                    context.interpolationQuality = .high
                    context.draw(cg, in: CGRect(origin: .zero, size: size))
                    return context.makeImage()
                }
                rows.append(SheetRow(label: name, cells: [shot]))
            }
            page.close()
        }
        SpikeRunner.record("branding_total", "visible_chromium=\(total) strings_chromium=\(strings)")
        // Each logo on its own (an image document; the pages' canvases cannot read chrome://theme).
        for address in logoURLs.sorted() {
            guard let url = URL(string: address), let page = await open(url, timeout: 10) else { continue }
            try? await Task.sleep(for: .milliseconds(500))
            let size = await js(page, "JSON.stringify([document.images[0]?.naturalWidth ?? 0, document.images[0]?.naturalHeight ?? 0])")
            let mean = await js(page, """
                (() => { const i = document.images[0]; if (!i) return 'none'; const c = document.createElement('canvas'); c.width = i.naturalWidth; c.height = i.naturalHeight;
                  const x = c.getContext('2d'); x.drawImage(i, 0, 0); const d = x.getImageData(0, 0, c.width, c.height).data; let r = 0, g = 0, b = 0, n = 0;
                  for (let k = 0; k < d.length; k += 4) if (d[k + 3] > 128) { r += d[k]; g += d[k + 1]; b += d[k + 2]; n++; }
                  return [r, g, b].map(v => Math.round(v / Math.max(n, 1))).join(','); })()
                """)
            SpikeRunner.record("branding_logo", "\(address) size=\(size) mean=\(mean)")
            page.close()
        }
        notificationIcon()
        if let sheets, !rows.isEmpty {
            // Two pages a row.
            var paired: [SheetRow] = []
            for index in stride(from: 0, to: rows.count, by: 2) {
                let second = index + 1 < rows.count ? rows[index + 1] : nil
                paired.append(SheetRow(label: rows[index].label + (second.map { " · " + $0.label } ?? ""),
                                       cells: [rows[index].cells.first ?? nil, second?.cells.first ?? nil]))
            }
            let appearance = NSApp.effectiveAppearance.isDark ? "dark" : "light"
            let sheet = ContactSheet(title: "Phase 5.2 — Chrome's pages in Room (B-103), \(appearance)", columns: ["page", "page"],
                                     notes: ["//room/branding: the theme's logos from the Room icon's glyph (Engine/roomcore/room/branding/theme), every locale string "
                                             + "naming Chromium overridden at startup (room_branded_strings.cc). The open-source attribution keeps Chromium's name."],
                                     rows: paired)
            let file = sheets.appending(path: "phase-5.2-branding-\(appearance)\(UserDefaults.standard.string(forKey: "RoomMatrixSuffix").map { $0.isEmpty ? "" : "-" + $0 } ?? "").png")
            SpikeRunner.record("sheet_branding", sheet.write(to: file) ? file.lastPathComponent : "failed")
        }
    }

    /// The alerts helper (macOS shows its icon on Room's notifications) against Room's own icon.
    private func notificationIcon() {
        let framework = Bundle.main.privateFrameworksURL?.appending(path: "RoomCore.framework/Versions/Current/Helpers")
        for helper in ["Room Helper (Alerts).app", "Room Helper (Aperitif Alerts).app"] {
            guard let path = framework?.appending(path: helper).path, FileManager.default.fileExists(atPath: path) else {
                SpikeRunner.record("branding_notification_icon", "\(helper): missing")
                continue
            }
            let mean = { (image: NSImage) -> String in
                let side = 64
                guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
                                                 hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return "?" }
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
                NSGraphicsContext.restoreGraphicsState()
                var r = 0, g = 0, b = 0, n = 0
                for y in 0..<side { for x in 0..<side {
                    guard let c = rep.colorAt(x: x, y: y), c.alphaComponent > 0.5 else { continue }
                    r += Int(c.redComponent * 255); g += Int(c.greenComponent * 255); b += Int(c.blueComponent * 255); n += 1
                } }
                return n == 0 ? "empty" : "\(r / n),\(g / n),\(b / n)"
            }
            let icns = URL(fileURLWithPath: path).appending(path: "Contents/Resources/app.icns")
            let roomIcns = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
            let same = roomIcns.flatMap { try? Data(contentsOf: $0) } == (try? Data(contentsOf: icns))
            SpikeRunner.record("branding_notification_icon", "\(helper): bundle icon mean=\(mean(NSWorkspace.shared.icon(forFile: path))) "
                + "app.icns mean=\(NSImage(contentsOf: icns).map(mean) ?? "unreadable") same bytes as Room's AppIcon.icns=\(same) "
                + "Room's icon mean=\(mean(NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)))")
        }
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
#endif
