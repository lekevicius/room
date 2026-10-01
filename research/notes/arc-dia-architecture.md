# Arc / Dia architecture (The Browser Company) — published-information research

Date: 2026-10-01. Scope: what has been *published* (talks, posts, podcasts, job ads, repos, press) about how The Browser Company (TBC) builds Arc and Dia as a Chromium engine under a Swift-written browser chrome, what "ADK" is, and where things stand after the Atlassian acquisition. Direct inspection of the installed `Arc.app`/`Dia.app` bundles is covered by the sibling note `arccore-adk-bundle-analysis.md`; this note cross-references it but does not repeat it.

Confidence legend: **[verified]** = primary or near-primary source quoted; **[reported]** = secondary press/aggregator; **[inferred]** = my reading, not stated by TBC.

---

## Summary

- Arc and Dia are **not** "Chromium with a patched UI". TBC's co-founder/CTO and its engineers describe the approach as turning Chromium into an *SDK* ("essentially an Electron out of Chromium", "take Chromium and turn it into a little SDK and just embed that in a normal Mac app… the same way… you've used the WebKit integration, it's just a view") and writing the entire browser chrome as a normal native Swift macOS app on top. The job ads say the same in one sentence: "we packaged Chromium as an SDK and wrapped our Swift code around it."
- That SDK is what Josh Miller's May 2025 letter calls **ADK — the Arc Development Kit**: "an internal SDK for building browsers (especially those with imaginative interfaces)… it lets ex-iOS engineers prototype native browser UI quickly, without touching C++." It is the stated reason Arc cannot be open-sourced. (Nate Parrott called the same thing "EDK" in a 2022 podcast transcript — probably the same concept, possibly a transcription error.)
- UI framework history: Arc's Mac UI was a mix of **SwiftUI and AppKit**, with business logic in a **private early fork of TCA** (The Composable Architecture). For Dia (2025) TBC **dropped SwiftUI and TCA**: "On Mac, we now use AppKit exclusively. We found that any use of SwiftUI (on Mac specifically) consistently regressed performance," using "a modified version of MVVM that… avoids state diffing", "optimized for cross-platform code sharing".
- Interop: TBC has never published the macOS Swift↔Chromium bridging mechanism. Published material covers only the *Windows* side (Swift calling WinRT/COM/C++ via `swift-winrt` and Swift 5.9 C++ interop). The bundle analysis (sibling note) shows the macOS answer: a Chromium fork built into `ArcCore.framework` exposing a hand-written/generated **Objective-C API** (`arc/browser/objcpp/*.h`, module `ArcCore`) that Swift imports directly. This is consistent with everything TBC has said publicly.
- Status (Oct 2026): Arc is in maintenance mode (weekly Chromium security bumps only; on Chromium 154 as of late Sept 2026). TBC was acquired by Atlassian ($610M cash, announced 2025-09-04, closed 2025-10-21). Dia is the sole product focus, GA on Apple-silicon Macs, Windows in open beta with a "fall 2026" public launch target. **Nothing of Arc or ADK has been open-sourced**, and no further description of ADK has been published since May 2025.
- Open-source precedents for "Swift chrome over Chromium" exist but are small: `mori-browser` (SwiftUI + Objective-C++ chrome compiled into the `chrome` target of ungoogled-chromium), `CefSwift` and `cha` (Swift/AppKit over CEF).

---

## Verified facts (each with source)

### Architecture statements from TBC people

1. **[verified]** Arc = Chromium + Swift; original prototype was a forked Electron with React, abandoned because "JavaScript is single threaded, and that single thread keeps getting blocked, especially when you're loading web pages." They then "built essentially an Electron out of Chromium" so that everything could be written in Swift. UI: "Arc UI is built in Swift instead of JavaScript… a lot of them are SwiftUI… Others use AppKit." A WebKit-backed build exists internally but is not shipped ("it doesn't have extension support and dev tools"). — Hursh Agrawal (co-founder/CTO), Syntax.fm #514, Sept 2022: https://syntax.fm/show/514/supper-club-arc-browser-with-hursh-agrawal/transcript
2. **[verified]** "Most Chromium browsers… write patches on top of Chromium… Brave, Edge… And so, we tried a different approach, which we called EDK. The idea was to take Chromium and turn it into a little SDK and just embed that in a normal Mac app in the same way that… you've used the WebKit integration, it's just a view that you can put into any app." Also: Boosts "are just Chrome extensions" (Arc writes a generated extension to disk as you type and reloads). — Nate Parrott, ShopTalk Show #545 (2022): https://shoptalkshow.com/545/
3. **[verified]** "we packaged Chromium as an SDK and wrapped our Swift code around it. Our Swift code base is shared across MacOS, Windows, iOS and Android." Role: "improving Dia's embedded-Chromium architecture", "Chromium on-call rotation and manage upstream updates", "Design APIs for seamless product integration". Requires 5+ yrs C++ and Chromium experience, willingness to learn Swift. — TBC "Staff Software Engineer, Chromium" job ad (removed July 2026): https://www.builtincolorado.com/job/software-engineer-chromium/10194923
4. **[verified]** "Arc is a Swift/Chromium web browser… on multiple platforms"; the compilers team "implemented the protocol that enables us to run our Swift code across MacOS, Windows, iOS and Android"; Swift chosen over C++ "to address challenges around slow iteration speed and memory safety". — TBC "Staff Systems Engineer, Compilers" job ad: https://builtinvancouver.org/job/staff-systems-engineer-compilers/4763084
5. **[verified]** Arc's architecture: "the majority of the business logic is shared code, and TCA provides for a natural split between the business logic and UI logic"; TBC maintained a **fork of TCA** because upstream depended on Combine (Apple-only). — Saleem Abdulrasool (@compnerd) relayed by Brandon Williams on the Swift Forums: https://forums.swift.org/t/using-tca-on-windows/71606 . TBC's public forks: https://github.com/thebrowsercompany/swift-composable-architecture , `open-combine-schedulers` (OpenCombine-based schedulers for Windows).
6. **[verified]** Dia drops SwiftUI and TCA: "Specifically, sunsetting our use of TCA and SwiftUI to make Dia lightweight, snappy, and responsive." — Josh Miller, "Letter to Arc members 2025", 2025-05-26: https://browsercompany.substack.com/p/letter-to-arc-members-2025
7. **[verified]** Follow-up by Josh Miller on X (quoted by Michael Tsai): "We use a modified version of MVVM that retains many ideas from unidirectional data flow architectures, but avoids state diffing for performance reasons." "This new architecture is optimized for cross-platform code sharing, making it easier to port Dia to Windows." "On Mac, we now use AppKit exclusively. We found that any use of SwiftUI (on Mac specifically) consistently regressed performance." — https://x.com/joshm/status/1927466374781079799 via https://mjtsai.com/blog/?p=47898 . Stephen Celis clarified Arc used "an early, specialized branch of TCA that differed significantly from the officially released version" — https://x.com/stephencelis/status/1927223344954319161 (via https://fatbobman.com/en/weekly/issue-086/).
8. **[verified]** Arc FAQ: Chromium-based, "supports 100% of the Extensions that Chrome supports", Google ad-business features "stripped away" (list published), and "we've built Arc in a way that makes it easy to swap rendering engines in the future… we may offer a WebKit version one day". — https://arc.net/faq
9. **[verified]** Arc on iOS (Arc Search / Arc mobile) uses WebKit; desktop uses Blink/V8. — https://en.wikipedia.org/wiki/Arc_(web_browser)

### ADK

10. **[verified]** "Arc isn't just a Chromium fork. It runs on custom infrastructure we call ADK — the Arc Development Kit. Think of it as an internal SDK for building browsers (especially those with imaginative interfaces). It's the main reason we were able to build Arc in the first place — it lets ex-iOS engineers prototype native browser UI quickly, without touching C++… While we'd love to open-source Arc someday, we can't do that meaningfully without also open-sourcing ADK. And ADK is still core to our company's value… If the day comes where it no longer puts our team or shareholders at risk, we'd be excited to share what we've built with the world. But we're not there yet." — Josh Miller, 2025-05-26: https://browsercompany.substack.com/p/letter-to-arc-members-2025 (also reported at https://heise.de/-10414231 and https://gigazine.net/gsc_news/en/20250608-letter-to-arc-members)
11. **[verified]** Same letter on Arc maintenance: TBC continues "regular Chromium upgrades, fix security vulnerabilities, related bugs, and more", but no new features; Dia is built on the same ADK ("the same tech they're using to build Dia" — https://gigazine.net/gsc_news/en/20250608-letter-to-arc-members).

### Windows port (how engine vs UI is split across platforms)

12. **[verified]** TBC chose to port Swift to Windows rather than rewrite Arc in C++; Arc for Windows uses **WinUI 3** ("the native UI framework of choice on Windows… built using WinRT") via a code-generated Swift projection of WinRT, open-sourced as `swift-winrt`. — Steve Brix (TBC), "Swift, meet WinRT", 2023-10-30: https://speakinginswift.substack.com/p/swift-meet-winrt ; repo https://github.com/thebrowsercompany/swift-winrt (854★, still pushed Sept 2026).
13. **[verified]** Interop strategy on Windows: Swift 5.9 C++ interop for cross-platform C++ libraries (e.g. `swift-firebase` wrapping Firebase's C++ SDK); COM bridges "neatly to Swift" because both are reference-counted; C shims where C++ interop is insufficient. — Saleem Abdulrasool, "Interoperability: Swift's Super Power", 2023-09-20: https://speakinginswift.substack.com/p/interoperability-swifts-super-power ; swift.org blog version: https://www.swift.org/blog/swift-everywhere-windows-interop/
14. **[verified]** TBC's Windows toolchain work continues under Atlassian: "Swift on Windows: A year of refinement" (2026-07-29, CMake-based runtime builds, Experimental Swift SDK for Windows, static linking) and "A Public Symbol Server for Swift on Windows" (2026-05-20). — https://speakinginswift.substack.com/p/swift-on-windows-a-year-of-refinement , https://speakinginswift.substack.com/p/a-public-symbol-server-for-swift
15. **[verified]** TBC GitHub org (fetched via GitHub API 2026-10-01): `swift-build` (toolchain CI, 390★, pushed 2026-10-01), `swift-winrt`, `swift-winui`, `swift-windowsappsdk`, `swift-windowsfoundation`, `swift-uwp`, `swift-cwinrt`, `swift-win2d`, `swift-webdriver` (UI testing via WinAppDriver), `windows-samples`, `swift-firebase` (+ `firebase-cpp-sdk` fork), `swift-sentry`/`sentry-native`, `swift-composable-architecture` fork, `open-combine-schedulers`, `GRDB.swift` fork, `Sparkle` fork, `Motion` (animation engine fork), `breakpad` mirror, `CMake` mirror, `swift` fork. **None of them contain any Chromium integration code**; all are Windows-toolchain, platform-binding, or dependency forks. — https://github.com/thebrowsercompany
16. **[verified]** Chromium's own build system has no Swift support; chromium-dev advice is to wrap in Objective-C(++) frameworks or link prebuilt Swift — i.e. the bridge has to be ObjC on macOS. — https://groups.google.com/a/chromium.org/g/chromium-dev/c/d4jXkf6A658
17. **[reported]** Arc for Windows: beta Dec 2023, GA 2024-04-30, Win 11 first then Win 10; "first app ever brought to Windows using Swift"; Windows team led by Alexandra Medway with Darin Fisher (ex-Chrome VP) and Saleem Abdulrasool. — https://techcrunch.com/2023/12/11/arc-browser-launches-its-windows-client-in-beta/ , https://www.thurrott.com/?p=301845 , https://www.engadget.com/the-excellent-and-customizable-arc-browser-is-now-fully-available-on-windows-165707711.html

### Features / product mechanics

18. **[verified]** Profiles scope "Logins, Cookies, Browsing History, Archive timing, and other settings to one or multiple Spaces"; Profiles do not sync, but Spaces/Tabs do. — Arc help: https://resources.arc.net/hc/en-us/articles/19227964556183
19. **[verified]** Boosts = CSS/JS/HTML customizations, implemented as generated Chrome extensions (see #2). Boosts 2.0 (2023) added no-code color/font/"zap" controls. — https://en.wikipedia.org/wiki/Arc_(web_browser) , https://shoptalkshow.com/545/
20. **[reported]** Air Traffic Control = routing rules that send externally-opened links to a chosen Space; Little Arc = floating mini-window for links opened from outside Arc; Peek = pop-up preview for links from pinned tabs; Split View; auto-archive of unpinned tabs after a configurable period. — https://allthings.how/how-to-route-links-to-specific-arc-spaces-using-air-traffic-control-in-the-arc-browser/ , https://en.wikipedia.org/wiki/Arc_(web_browser)
21. **[verified]** Arc requires an account; sync is TBC's own (Firebase is referenced in TBC's interop post as used by Arc), not Chrome Sync; extensions and history do not sync. — https://arc.net/faq , https://speakinginswift.substack.com/p/interoperability-swifts-super-power , https://mjtsai.com/blog/2023/05/03/arc-browser/

### Status

22. **[verified]** Atlassian–TBC: definitive agreement 2025-09-04, $610M cash; closed 2025-10-21. — https://techcrunch.com/2025/09/04/atlassian-to-buy-arc-developer-the-browser-company-for-610m/ , https://investors.atlassian.com/news/news-details/2025/Atlassian-Completes-Acquisition-of-The-Browser-Company-of-New-York/default.aspx
23. **[verified]** Josh Miller at announcement: "Dia will remain our focus, with new resources to bring it to other platforms faster" (Mac, Windows, iOS, Android, enterprise); "Arc and Arc Search will continue to exist, and we'll share a long-term plan soon." — https://browsercompany.substack.com/p/your-tuesday-in-2030 (2025-09-04). No such long-term plan has been published as of 2026-10-01 that I could find.
24. **[reported]** Arc releases 2026 are Chromium security bumps only: Chromium 148 (May), 149 (June), 150 (July), 151–152 (Aug), 153 (Sept 10/17), **154.0.8037.58 (Sept 24, 2026)** for both macOS and Windows; one Windows Split-View resize fix in Aug. — https://releasebot.io/updates/arc , https://supasidebar.com/blog/arc-browser-status-tracker , official notes: https://resources.arc.net/hc/en-us/articles/20498293324823-Arc-for-macOS-2024-2026-Release-Notes
25. **[reported]** Dia: announced Dec 2024, beta June 2025, Pro $20/mo (Aug 2025), public macOS launch 2025-10-09, Apple-silicon only (macOS 14+), v1.33 by May 2026 with cross-device sync and Confluence "Live Groups"; Spaces shipped July 2026; Windows beta ("Windows Wednesdays") opened July 29 2026, >2,500 testers by Aug 6, public launch targeted "fall 2026"; still beta on 2026-09-06. — https://supasidebar.com/blog/dia-browser-status-tracker , https://piunikaweb.com/2026/07/30/dia-windows-slated-officially-launch-fall-2026/ , https://piunikaweb.com/2026/08/06/dia-morning-brief-windows-progress/ , https://piunikaweb.com/2026/09/06/dia-progress-windows-version-live-groups/
26. **[reported]** Dia is "written in Swift and built on Chromium". — https://www.digitaltrends.com/?p=5994158 (consistent with TBC job ads, #3).
27. **[reported]** No open-source Arc or ADK exists as of mid-2026; no repo, no license. — https://supasidebar.com/blog/open-source-arc-browser

### Other Chromium browsers' UI technology (Q6)

28. **[verified]** Chromium's cross-platform UI is the **Views** toolkit; on macOS Views is hosted through `ui/views_bridge_mac` (Cocoa NSWindow/NSView hosts), so stock Chromium/Chrome UI on Mac is Views-drawn, not AppKit controls. — https://chromium.googlesource.com/chromium/src/+/main/ui/views/ , https://chromium.googlesource.com/chromium/src/+/HEAD/docs/ui/learn/glossary.md
29. **[verified]** Vivaldi's browser UI is a React/HTML/CSS app. — https://forum.vivaldi.net/topic/5347/technologies-behind-vivaldi-browser/13
30. **[reported]** Brave dropped its Electron/Muon shell in 2018 and now uses Chromium's UI (Views + WebUI for panels). — https://www.computerworld.com/article/3328781/brave-browser-goes-full-chromium-by-adopting-google-ui.html
31. **[verified]** Helium = ungoogled-chromium with patch sets (Inox, Debian, Bromite, Iridium, Brave); UI is stock Chromium Views; GPL-3 for Helium-specific code. — https://github.com/imputnet/helium
32. **[reported]** Comet (Perplexity) = Chromium fork with an assistant sidebar; no published statement of UI toolkit (presumed Views/WebUI). Sidekick was acquired by Perplexity (May 2025) and sunset 2025-08-03. Wavebox moved from Electron to a direct Chromium fork. — https://www.theregister.com/2025/07/09/perplexity_comet_browser/ , https://www.superchargebrowser.com/library/sidekick-browser-shutdown-chrome-alternative/ , https://hub.wavebox.io/wavebox-is-evolving-our-move-to-chromium/
33. **[verified]** Open-source "Swift chrome over Chromium" projects:
    - **mori-browser** — "custom SwiftUI + Objective-C++ chrome compiled into the `chrome` target of an ungoogled-chromium checkout… not a fork of Chromium's UI and not a CEF app." Layers: SwiftUI chrome (sidebar, launcher, panels, theming, shortcuts) → Objective-C++ bridge (commands, tabs, windows, downloads) → Chromium (renderer, navigation, extensions, permissions). Code lives in `chrome/browser/ui/mori/`, built with GN/Ninja. MIT, "experimental". — https://github.com/FujiwaraChoki/mori-browser
    - **CefSwift** — CEF in SwiftUI; three hosting modes (Alloy NSView, Chrome-runtime window with tabs/extensions/chrome:// pages, OSR Metal/IOSurface); BSD-3; lacks native extensions/sync in the NSView mode. — https://github.com/Rajaniraiyn/CefSwift
    - **cha** — "Arc-like browser for macOS: native Swift interface on Chromium via CEF"; AppKit window + sidebar, each tab a frameless CEF child window; ObjC++ `ChaEngine`/`ChaTab`; 3 commits. — https://github.com/stasiandr/cha

---

## Architecture as best understood

### Engine/UI boundary
- **Engine side**: a Chromium fork built as a single embeddable framework. TBC compares it to WKWebView: "just a view that you can put into any app" (#2). The job ads call it "embedded-Chromium architecture" and "packaging Chromium as an SDK" (#3). The sibling bundle note confirms the artifact: `ArcCore.framework` (bundle id `company.thebrowser.browser.framework`) containing the Chromium binary, helper apps (Browser Helper / GPU / Renderer / Alerts), `.pak` resources and DevTools — i.e. the *whole* Chromium browser process including `//chrome`-layer services (extensions, autofill, password manager, omnibox autocomplete, bookmarks, history, session restore, translate, PDF, DevTools), not a bare `//content` shell.
- **UI side**: a separate Swift executable that owns `NSApplication`, every `NSWindow`, the sidebar, command bar, split view, Little Arc etc. All Chrome UI that normally comes from Views (context menus, permission prompts, JS dialogs, save-password bubbles, extension popups, HTTP auth, hung-renderer dialogs…) is re-implemented natively in Swift, driven by delegate callbacks from the framework (sibling note §2). This matches Hursh's "build everything in Swift" and Josh's "ex-iOS engineers prototype native browser UI… without touching C++".
- **Who runs the main loop**: per the bundle note, the ObjC `ArcBrowserApplication.run` runs Chromium's main loop, which in turn drives `NSApplication`. Nothing published contradicts this. [inferred from bundle + Chromium's `BrowserMainRunner` design]

### Interop mechanism (macOS)
- **Never published by TBC.** All first-party interop writing is about Windows (WinRT/COM/C++ interop, #12–14).
- Chromium's build (GN/Ninja) cannot compile Swift (#16), and TBC's "no C++ for product engineers" goal (#10) implies a stable language boundary. The bundle note shows the boundary is **Objective-C headers generated/hand-written from Objective-C++ implementations** (`arc/browser/objcpp/`), exported with an umbrella header and `module.modulemap` so Swift does `import ArcCore`. That is exactly the "Objective-C wrapper framework" pattern Chromium engineers recommend (#16) and the pattern `mori-browser` and `cha` use (#33). No evidence that TBC uses Swift 5.9 C++ interop *on macOS* for Chromium; their C++ interop usage is documented only for Firebase and Windows APIs.
- Consequence: Chromium is patched/extended inside the fork to expose ObjC-facing services, but product code never sees C++. Chromium upgrades are owned by a dedicated Chromium team with an on-call rotation (#3).

### UI framework
- Arc (2022–2025): SwiftUI + AppKit mix (#1), TCA-fork business logic (#5), shared across Mac/Windows; Windows UI in WinUI 3 through `swift-winrt` projections (#12).
- Dia (2025→): **AppKit only on Mac**, SwiftUI removed for performance; TCA replaced by a custom MVVM "without state diffing"; architecture designed for Windows sharing (#6, #7). Dia on Windows is in beta with the same Swift codebase (#3, #25).
- Dependencies visible in the public forks/bundle: GRDB (SQLite), Sparkle (updates), Sentry, Lottie, Motion, Combine (Mac) / OpenCombine (Windows), Firebase (auth/sync), LaunchDarkly (flags), Segment analytics, MLX (Dia local models).

### Chrome features
- Extensions / Chrome Web Store: supported "100%" (#8); Boosts are generated extensions (#2). Extension popups, install consent and `chrome.tabs/tabGroups` bridging are surfaced to Swift via delegates (bundle note).
- Passwords/autofill: Chromium's password manager and autofill logic are kept; the *prompts* are native (bundle note delegate list).
- Google services: Google-account-dependent features (Chrome Sync, Google ad/measurement services) are stripped; Arc publishes a list of disabled Chrome features (#8). Sync is TBC's own Firebase-backed account (#21). Spaces/Profiles map to separate Chromium browser contexts (#18; `ArcBrowserContext` ≈ `Profile` in bundle note).
- Performance mechanics: tab discard/freeze votes and archived (suspended) tabs are exposed to the Swift side (bundle note); auto-archive is a product rule on top (#20). No published TBC engineering post on tab-archiving internals exists.

---

## What ADK is

- **Stated by TBC** (#10): an internal SDK for building browsers; "custom infrastructure"; lets ex-iOS engineers "prototype native browser UI quickly, without touching C++"; shared by Arc and Dia; "core to our company's value"; the blocker for open-sourcing Arc.
- **Stated by engineers earlier under another name** (#2, "EDK"): Chromium turned into "a little SDK" embedded in "a normal Mac app", WKWebView-style, as an alternative to the Brave/Edge "patches on top of Chromium" model, explicitly to make zero-day merges cheap.
- **What that implies / what the bundle confirms**: ADK = (a) a maintained Chromium fork, (b) build/packaging into one framework per platform (macOS framework; presumably a DLL on Windows), (c) an Objective-C (macOS) API surface over `Profile`/`Browser`/`WebContents` plus delegates for every piece of Chrome UI, (d) the Swift-side libraries and conventions product engineers build on. On Windows the same Swift code talks to Chromium through an equivalent (unpublished) C/C++ surface and to the OS through `swift-winrt`.
- **"macOS native Chromium SDK"** is a fair paraphrase but TBC has never used those words; they say "internal SDK for building browsers".
- Nothing further about ADK has been published between May 2025 and Oct 2026 — not in the Atlassian announcements, not on Speaking in Swift, not in Josh Miller's posts.

---

## Current status of Arc / Dia / TBC (as of 2026-10-01)

| Item | Status | Source |
|---|---|---|
| TBC ownership | Atlassian subsidiary since 2025-10-21 ($610M cash); Miller/Agrawal still CEO/CTO; "operates independently" | #22, #23 |
| Arc (macOS, Windows) | Maintenance mode since 2025-05-26: weekly Chromium security bumps, no features. Latest: Chromium 154.0.8037.58 (2026-09-24) | #11, #24 |
| Arc open source / ADK | Not open-sourced; no timeline; no new description of ADK since May 2025. The promised "long-term plan" for Arc has not appeared | #10, #23, #27 |
| Dia macOS | GA since 2025-10-09; Apple-silicon only; freemium + $20/mo Pro; sync, Spaces, Tab/Live Groups, Confluence/Notion/Slack integrations; local MLX models in bundle | #25, bundle note |
| Dia Windows | Open beta since 2026-07-29 (>2,500 testers by Aug 6; admitted daily); public launch targeted "fall 2026"; still beta on 2026-09-06 | #25 |
| Dia iOS | Not shipped; leaked evidence of development (Sept 2026) | #25 (piunikaweb 09-06) |
| TBC Swift-on-Windows work | Continues (toolchain post July 2026, symbol server May 2026, `swift-build` pushed 2026-10-01) | #14, #15 |
| Arc Search (iOS/Android) | Still updated (security/stability), WebKit on iOS | #9, #24 |

---

## Lessons for our project

1. **The shape is validated.** A proprietary, VC-funded team with ex-Chrome leadership chose: Chromium fork → one embeddable framework exposing a WebKit-style ObjC API → a normal Swift/AppKit Mac app. Three independent OSS projects (mori, cha, CefSwift) converge on the same layering. We should do the same, not try to drive Views or write Swift inside the GN build.
2. **Bridge in Objective-C(++), not Swift C++ interop.** GN can't compile Swift; Chromium's maintainers themselves recommend an ObjC wrapper framework; TBC's product engineers "never touch C++". Keep the boundary as a modulemap'd ObjC framework, with `NS_SWIFT_UI_ACTOR`/main-actor semantics, and keep the Swift side a separate Xcode/SwiftPM target that links the framework. Use Swift C++ interop only for isolated cross-platform libs (TBC's precedent: Firebase).
3. **Embed the `//chrome` layer, not just `//content`.** The value of ADK is that extensions, autofill, password manager, omnibox autocomplete, session restore, translate, PDF and DevTools come "for free" from Chromium while only their *UI* is rebuilt. CEF-style content-only embedding (CefSwift's NSView mode, cha) loses extensions/sync — Hursh explicitly cites extension + DevTools support as the reason the WebKit variant never shipped.
4. **Budget for the delegate surface.** Every Views dialog Chromium would have shown becomes a Swift delegate you must implement (context menus, permissions, JS dialogs, auth, save-password/credit-card bubbles, extension popups, hung renderer, external protocol, fullscreen, pointer lock…). That list (sibling note §2) is a ready-made backlog and the real cost of "native UI".
5. **AppKit, not SwiftUI, for the chrome.** TBC ran a multi-year SwiftUI+TCA experiment on macOS and reversed it for performance ("any use of SwiftUI on Mac consistently regressed performance"). Start with AppKit for the sidebar/tab strip and use SwiftUI only for leaf views you can afford to be slow. Avoid state-diffing architectures on hot paths (tab lists with hundreds of items).
6. **Treat Chromium upgrades as a product function.** TBC's model is "ADK as SDK" precisely so that zero-day merges don't touch product code; they still staff a Chromium team with an on-call rotation. Keep fork patches minimal and concentrated in the API layer; automate weekly Chromium bumps from day one (Arc has been shipping security-only weekly bumps for 16 months with essentially no feature work).
7. **Spaces = browser contexts.** Arc's Profiles-per-Space model maps directly to Chromium `Profile`s; Air Traffic Control is a `decidePolicyForNavigationAction`-style hook. Design the API so a window (`Browser`) can host `WebContents` from different contexts.
8. **Features as extensions.** Boosts being generated Chrome extensions is a cheap way to ship user CSS/JS without touching the renderer; the same trick works for "zap"-style tools.
9. **Don't expect to reuse TBC code.** Nothing Chromium-related is public; the public repos are Windows toolchain and dependency forks. The useful public artifacts are `swift-winrt`/`swift-winui` (only if we ever go to Windows), `swift-webdriver` (UI testing idea), and the forks list as a dependency shopping list (GRDB, Sparkle, Sentry, Lottie, Motion).

---

## Open questions

1. **Build integration**: how does TBC build `ArcCore.framework` — a GN target inside the Chromium tree (like mori's `chrome/browser/ui/<name>/`) or an out-of-tree wrapper? How is the ObjC API generated ("hand-written plus code-generated" per bundle note — generated from what IDL)? No public source.
2. **Main-loop ownership**: does Chromium's `BrowserMainLoop` own `NSApplication` (bundle suggests `ArcBrowserApplication.run`), and how do they reconcile that with Sparkle/AppKit lifecycle? Not published.
3. **Windows engine boundary**: on Windows the Swift↔Chromium surface can't be ObjC. Is it a C API (`swift-cwinrt`-style), COM, or Swift C++ interop? Unknown; TBC never described it.
4. **Rendering/compositing**: does the Chromium compositor render into its own `NSView` (`nativeView` in bundle), and how do they layer Swift views (sidebar, Little Arc, Peek) over/beside it without IOSurface tricks? Not published.
5. **Arc "long-term plan"** promised Sept 2025: never published. Will Atlassian ever open ADK? No signal either way after the acquisition.
6. **Dia Windows launch**: targeted fall 2026; still beta on 2026-09-06; no public date as of 2026-10-01.
7. **Comet/other AI browsers' UI stack**: no published confirmation whether Comet uses Views, WebUI or anything native; presumed Views.
8. **EDK vs ADK**: the 2022 "EDK" (podcast transcript) vs 2025 "ADK" — same kit renamed, or a transcription error? Unverified.
9. **Memory/tab-archiving internals**: only product-level descriptions exist; the discard/freeze API in the bundle suggests they lean on Chromium's own tab discarding plus app-level archiving, but no engineering write-up exists.

---

### Sources not usable / dead ends (for the record)
- TBC "Developer Infrastructure Team" Notion page (https://browserinc.notion.site/...f99098e649ab4fafa99f061d5b1f6194) renders empty to fetchers; press summaries say it lists contributions to the Swift VS Code extension, SourceKit-LSP, lldb, the Swift compiler and CMake.
- No TBC engineer talk on Swift↔Chromium bridging at NSSpain/SwiftConf/try! Swift/Chrome Dev Summit was found; TBC's conference presence is Saleem Abdulrasool on Swift-on-Windows (incl. Empower Apps podcast, Aug 2026 per https://www.swift.org/blog/whats-new-in-swift-august-2026/).
- Hacker News (Algolia API) has no comments from TBC staff describing the bridge; community comments only note "non-V8/Blink bits are almost entirely Swift" and "uses SwiftUI instead of Chromium's UI framework".
- TechCrunch's May 27 2025 ADK article URL could not be fetched directly; its content is reflected in #10 via the primary letter and heise/gigazine.
