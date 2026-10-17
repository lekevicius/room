# Built-in ad and tracker blocking: approach (B-30)

2026-10-17. This is step 1 of B-30's blocking work: a comparison and a recommendation. No fork work has been done; Step 2 waits for the user's decision (§7).

Checkout: `~/chromium/src` at 155.0.8059.36 plus the 23-patch series. Paths below are relative to it unless they start with `room/` or `Engine/`.

## 1. What the product needs

- **The user's ask:** "built-in ad blocking with good default lists, but customizable."
- **Defaults:** ads and trackers blocked out of the box, from well-maintained open lists.
- **Settings ▸ Privacy:**
  - Block ads on/off, Block trackers on/off.
  - The lists, with custom lists added by URL.
  - Custom rules.
  - Allowed sites.
- **Per-site toggle:** in the site panel.
- **No unrequested network calls** (CLAUDE.md). Automatic list updates sit behind a visible, explicit setting, the same way Sparkle and Sentry are opt-in in `OptInServices`.
- **Pillars:** Chromium without Google; ad blocking that is all open source; hand-crafted for macOS. The second pillar also rules out a blocker that is a black box.
- **Fork rules that bind every option:**
  - Our code lives in `//room`.
  - Patches are tiny hooks only.
  - PLAN §4 "Engine work in app chapters": no new patch in Chapters 4–5 without a user row.
  - PLAN §7 risk 1 is rebase cost.

## 2. Measured inputs

### 2.1 The lists (fetched 2026-10-17)

Rules are non-comment lines.

| List | Size | Rules | Expires | Licence |
|---|---|---|---|---|
| EasyList | 2,183,955 B | 83,221 (58,534 network, 24,687 element hiding) | 4 days | GPLv3+ or CC BY-SA 3.0+ ("The EasyList authors") |
| EasyPrivacy | 1,509,917 B | 56,345 (56,308 network) | 4 days | same |
| uBlock filters | 471,642 B | 6,078 (1,777 network, 4,301 cosmetic/scriptlet) | 5 days | GPLv3 (uAssets) |
| uBlock privacy | 183,932 B | 1,776 | 7 days | GPLv3 |
| uBlock badware | 261,388 B | 4,355 | 5 days | GPLv3 |
| uBlock quick fixes | 86,905 B | 468 | 8 hours | GPLv3 |
| uBlock unbreak | 280,658 B | 2,554 | 5 days | GPLv3 |
| Peter Lowe (hosts) | 95,518 B | 3,569 | none | **no licence stated** (pgl.yoyo.org invites reuse; nothing written) |

- **uBlock Origin's defaults** (`assets/assets.json`): the five uBlock lists, EasyList, EasyPrivacy, URLhaus and Peter Lowe.
- **Updates:** EasyList and EasyPrivacy carried `Version: 202610171524`, so they were updated the day they were fetched.

### 2.2 How much each list Chromium's own ruleset parser accepts

Method: I ran the lists through a classifier that mirrors `components/subresource_filter/tools/rule_parser/rule_parser.cc`, which is the parser option (a) depends on:
- **Supported options:** element types, `document`, `elemhide`, `generichide`, `genericblock`, `third-party`, `match-case`, `domain=`.
- **Rejected:** any unknown option fails the whole rule (`rule_parser.cc:339-343`), and regex rules are dropped (`url_pattern_index.cc:379-382`).
- **Element hiding:** `##` style rules are accepted only without `~domain` (`rule_parser.cc:437-441`).

| List | Network rules accepted | Cosmetic rules accepted | What fails |
|---|---|---|---|
| EasyList | 58,502 / 58,534 (**99.9 %**) | 24,400 / 24,687 (98.8 %) | 7 `rewrite`, 3 `csp`, 22 regex; 287 extended-syntax cosmetics |
| EasyPrivacy | 56,263 / 56,308 (**99.9 %**) | 2 / 37 | 29 `redirect`, 10 `important` |
| uBlock filters | 456 / 1,777 (**25.7 %**) | 1,601 / 4,301 (37.2 %) | `ghide` 405, `1p` 274, `3p` 206, `xhr` 165, `redirect` 164; 2,471 scriptlet or HTML filters |
| uBlock privacy | 824 / 1,451 (56.8 %) | 6 / 325 | `removeparam` 218, `doc` 211, `urlskip` 207 |

- **EasyList and EasyPrivacy** are written in ABP-compatible syntax, so Chromium's machinery takes them almost whole.
- **uBlock's own lists** are where the anti-adblock, YouTube and site-fix work lives: scriptlets (`+js(...)`), redirects, `removeparam`, procedural cosmetics. Chromium's machinery takes a quarter of their network rules and none of the scriptlets. Some failures are uBO aliases (`1p`, `3p`, `xhr`, `frame`, `ghide`) that a converter could rewrite; redirects, scriptlets and `removeparam` it could not.

### 2.3 uBlock Origin Lite's compiled default rulesets

Source: `uBOL-home/chromium/rulesets/ruleset-details.json`, manifest 2026.1012.1545.

| Ruleset | DNR rules | Regex | Source filters | Generic cosmetic | Specific cosmetic |
|---|---|---|---|---|---|
| ublock-filters | 5,763 | 207 | 10,653 | 673 | 5,149 |
| easylist | 3,727 | 18 | 57,050 | 12,328 | 8,284 |
| easyprivacy | 9,055 | 7 | 56,314 | 2 | 4 |
| pgl | 1 (3,457 `requestDomains`) | 0 | 3,548 | 0 | 0 |
| ublock-badware | 462 | 22 | 9,666 | 47 | 209 |
| urlhaus-full | 1 | 0 | 2,665 | 0 | 0 |
| **Defaults** | **19,009** | 254 | | 13,050 | 13,646 |

- uBO's compiler merges domain lists aggressively: EasyList's 57k filters become 3.7k DNR rules.
- All 56 uBOL rulesets total 70,941 rules.
- uBOL is installed from the Web Store and verified working in Room (3.6a, `spike-results.md`).

### 2.4 Churn in the code each option leans on

Commits in the year before 155 (2025-10-06 → 2026-10-06, `git log 155.0.8059.36 -- <path>`).

| Path | Commits |
|---|---|
| `components/subresource_filter` | 79 |
| `components/url_pattern_index` | 11 |
| `extensions/browser/api/declarative_net_request` | 27 |
| DNR's public IDL | 6 |
| `scripting` API (IDL + browser) | 4 |
| `third_party/rust/chromium_crates_io/Cargo.lock` | 501 |
| `build/config/rust.gni` | 17 |

Within subresource_filter, two of those changes are structural:
- The fingerprinting-protection filter, its second user, was deleted on 2025-11-24 (`b6d76c1f1e753`).
- Style-rule matching was added on 2026-05-14 (`6d6f26cb5af0d`). No production code consumes it yet.

## 3. Option (a): Chromium's subresource_filter ruleset machinery

**How it would work in Room.**
- **One ruleset for the whole browser.** `g_browser_process->subresource_filter_ruleset_service()` (`browser_process_impl.cc:1849-1866`) is a single global `RulesetService`.
- **Feeding it.** `//room` converts the enabled lists to Chromium's unindexed format and calls `RulesetService::IndexAndStoreAndPublishRulesetIfNeeded(UnindexedRulesetInfo)` (`ruleset_service.h:186`), the public method Google's "Subresource Filter Rules" component uses.
- **Turning blocking on everywhere.** Either:
  - a feature parameter, `SubresourceFilter:activation_scope/all_sites/activation_state/enabled` (`subresource_filter_features.cc:153-196, 255-263`; `ALL_SITES` is handled at `safe_browsing_page_activation_throttle.cc:353`); or
  - `subresource_filter::testing::GetAndSetActivateConfigurations`. It is a non-test header, but it sits in the `testing` namespace.
- **The ruleset reaches every renderer as a read-only memory-mapped file** (`safe_browsing_ruleset_publisher.cc:30-42`, `memory_mapped_ruleset.cc`). Blink's `DocumentSubresourceFilter` decides each fetch. Subframe navigations are blocked in the browser (`SafeBrowsingChildNavigationThrottle`).

**Network vs cosmetic.**
- **Network:** EasyList and EasyPrivacy are covered (§2.2, 99.9 %). Missing:
  - regex, `csp`, `redirect`, `removeparam`, `important`, `badfilter`;
  - scriptlets;
  - service workers and shared workers: only dedicated workers get a filter (`subresource_filter_agent.cc:378-391`).
- **Cosmetic:** the indexer stores `##` rules (`ruleset_service.cc:394-398`), and Blink exposes `GetDomainSelectors`, `GetSelectorsByClass` and `GetSelectorsById` (`web_document_subresource_filter.h:43-60`). **Nothing in Chromium calls them outside tests.** Element hiding would need our own renderer `RenderFrameObserver`, which needs a renderer-client hook, and that API is two releases old.
- **Lists:** uBlock's lists are effectively out (§2.2).

**Compilation and updates.**
- Conversion uses `//components/subresource_filter/tools:ruleset_converter`, a non-testonly host tool. Its parser could also be linked into `//room` to compile custom rules at runtime.
- Each change re-indexes the whole ruleset, then republishes it to every renderer. Indexing time for about 115k rules is unmeasured.
- Opt-in updates are easy: fetch the text, convert, re-index.

**Patches and rebase.**
- One hook stops Google's component from re-publishing its own ruleset over ours on every start (`registration.cc:155` → `RegisterSubresourceFilterComponent`).
- One hook in `ChromeContentRendererClient` lets the cosmetic observer exist.
- Total: **+2 patches**, plus `//room` code against a component with 79 commits a year, whose style-rule API is new and unused upstream.

**Memory and page load.**
- **Memory:** the best of the three. One page-cache copy is shared by all renderers.
  - Google's list is 158,519 B unindexed and 251,248 B indexed (×1.58, the CEF-era `Room/Engine/Subresource Filter/`).
  - EasyList plus EasyPrivacy (3.7 MB of text) would index to a few MB. That is an estimate, not measured.
- **Matching cost:** close to zero extra. `kAdTagging` is on by default, so every page already runs a dry-run activation with the ruleset (`content_subresource_filter_throttle_manager.cc:664-671`). RoomCore's ruleset directory is empty today, because component updates have been off since 3.1.
- **Costs of the `ALL_SITES` route:**
  - It runs through `SafeBrowsingPageActivationThrottle`, which needs Safe Browsing's database manager. Every navigation is checked, and `WillProcessResponse` defers until the check finishes (`:113-123`). That is Google's machinery in the path, against the first pillar.
  - It writes an `ADS_DATA` website setting for every activated site (`profile_interaction_manager.cc:113-117`).
  - A `//room` throttle instead of the Safe Browsing one only works if the database manager is null (`throttle_manager.cc:529-535`).

**Licences:** Chromium (BSD), plus the lists as data. EasyList and EasyPrivacy can be taken under CC BY-SA with attribution.

**Allowlist and custom rules.**
- Per-site: `ContentSettingsType::ADS` set to ALLOW through the ordinary `HostContentSettingsMap` (`subresource_filter_content_settings_manager`). It is only honoured on the Safe Browsing throttle path.
- Custom rules: appended to the text before conversion, with the same syntax limits.
- Ads and trackers as separate switches: one global ruleset, so each toggle rebuilds it.

**Effort:** about 1,000 `//room` lines (feed, configuration, cosmetic observer, allowlist), +2 patches.

## 4. Option (b): a bundled declarativeNetRequest extension (uBlock Origin Lite's approach)

**How it would work in Room.**
- **The extension.** Room ships an MV3 extension of its own: a fork of uBlock Origin Lite with its popup and dashboard removed, its settings read from `chrome.storage`, and nothing else changed.
- **Its rulesets.** The rulesets are compiled from the lists at Room's build time by uBO's own compiler (`platform/mv3/make-rulesets.js`), the one that produced §2.3.
- **Installing it.** `//room` installs the extension into every profile, hidden from the user. It is not listed in Settings ▸ Extensions: `IsListed()` is `ShouldDisplayInExtensionSettings`, `room_extensions.mm:122`, which hides component locations (`ui_util.cc:27-33`).
- **Driving it.** Room drives it from native code:
  - list toggles through `RulesMonitorService::UpdateEnabledStaticRulesets` (`rules_monitor_service.h:145`);
  - allowed sites as `allowAllRequests` dynamic rules through `UpdateDynamicRules` (`:106-110`). Both are public C++ in `//extensions/browser`, which `//room` already links.
  - Everything else is written into the extension's storage, which its scripts already observe.
- **Blocked counts** come from `RulesMonitorService::action_tracker()` (`:157`): per-tab matched-rule counts for the site panel.

**Network vs cosmetic.**
- **Network:** DNR covers block, allow, `allowAllRequests`, redirect (to packaged resources), `upgradeScheme`, `modifyHeaders` (`csp`), `removeparam` (via redirect transform), `topDomains`, response headers, and every resource type including `main_frame`, websockets, `webtransport` and service workers. Their factories are proxied (`content_browser_client.h:1846-1850`).
- **Cosmetic and scriptlets:** packaged CSS and JS registered with `scripting.registerContentScripts`. Generic and specific hiding, procedural filters and scriptlets come from uBlock's lists (§2.3: 13,050 generic and 13,646 specific selectors).
  - The CSS is author-origin: `registerContentScripts` has no `cssOrigin` (`scripting.webidl:122-170`). uBOL lives with this.
  - Component extensions bypass site-access withholding, so no host-permission prompt is needed (`permissions_data.cc:311-314`).
- **Limits** (`declarative_net_request.webidl`, `constants.h`):
  - 30,000 guaranteed static rules per extension, plus a 300,000 pool per profile;
  - 50 enabled static rulesets;
  - 1,000 regex rules;
  - 30,000 dynamic rules, of which 5,000 "unsafe" (redirect, `modifyHeaders`);
  - no exemption for component locations.
  
  uBOL's defaults use 19,009 rules and 254 regex.

**Compilation and updates.**
- **Default lists:** compiled at build time, then indexed once per install (flatbuffers, `url_pattern_index`; time-sliced at 50 ms, `install_index_helper.cc:197-212`). They refresh with every Room release; Sparkle is already opt-in.
- **Custom rules:** compiled at runtime by the same uBO compiler inside the extension, into dynamic rules plus registered content scripts.
- **Custom lists by URL:** fetched when the user adds one (an explicit action), compiled to dynamic rules, sharing the 30k dynamic pool. One EasyList-sized list is about 3.7k rules, so several fit.
- **Opt-in automatic updates:** the extension recompiles the upstream lists, and `//room` writes them as a new extension version and re-installs it, which re-indexes. This is the one novel piece. It is prototyped first in Step 2, and the step falls back to "lists update with Room releases" until it works.

**Patches and rebase.**
- **The install path is the one open question.**
  - `ComponentLoader::AddOrReplace(path)` is public and skips the allowlist (`component_loader.cc:388-403`).
  - But `ExtensionRegistrar::AddComponentExtension` passes empty ruleset install prefs (`extension_registrar.cc:597-601`, Chromium's own `TODO(crbug.com/40508457)`). Static rulesets then fail with `kErrorChecksumNotFound` (`rules_monitor_service.cc:602-608`).
  - Indexed rulesets are also written into the extension's own directory (`file_backed_ruleset_source.cc:255-262`), which must not be the signed bundle.
- **Three routes, in order of preference:**

  | Route | How | Cost |
  |---|---|---|
  | 1 | Copy the extension into the profile, index with `InstallIndexHelper::IndexStaticRulesets`, store the checksums with the public `PrefsHelper::SetStaticRulesetChecksum`, then `AddOrReplace` | 0 patches; it writes another subsystem's prefs |
  | 2 | `UnpackedInstaller` (which indexes and stores the prefs, `unpacked_installer.cc:329-351`), with Room's list filtering its id out | 0 patches; location `kUnpacked` (user-modifiable, visible in `chrome://extensions`) |
  | 3 | A ≤10-line hook that does Chromium's TODO in `AddComponentExtension` | +1 patch, a user row under PLAN §4 |

  An external-component install through `CrxInstaller` was checked and rejected: an external extension that no provider acknowledges is uninstalled at startup (`extension_service_unittest.cc:6344-6365`).
- **The extension itself** uses web-facing APIs that Chrome keeps compatible for Web Store extensions: DNR IDL 6 commits a year, `scripting` 4. Keeping up with uBOL is a JS merge in our repo, not Chromium rebase work.
- **Net cost:** 0–1 patch, plus about 400 `//room` lines against `RulesMonitorService` and `ComponentLoader` (27 commits a year in that directory).

**Memory and page load.**
- **Proxying:** with any DNR extension loaded, every URL loader factory in the profile is proxied through the browser process (`web_request_api.cc:182-190, 1013-1023`). The user already pays this with uBOL installed, as does every Chrome uBOL user. Unmeasured in Room; Step 2 measures fixture loads with and without.
- **Rule memory:** the indexed rules sit in the browser process, a few MB for about 19k rules (estimate).
- **Scripts:** the MV3 service worker is idle-terminated after 30 s, so its resting memory is near zero. Content scripts run per frame on matching hosts.

**Licences.**
- uBOL is GPL-3.0, so our fork of it is GPL-3.0 and its source must be public.
- Shipping it inside Room.app is aggregation of a separate program (GPLv3 §5). Room's own licence is unaffected. The repository is private with no licence today; that is a separate decision.
- uBO's compiler and scriptlets are GPLv3. EasyList uses CC BY-SA attribution. The uBlock lists are GPLv3 data, published with the extension's source.
- Peter Lowe's list has no stated licence: drop it, or ask pgl@yoyo.org.
- This fits the "all open source" pillar exactly: the whole blocker is a public GPL program whose lists and compiler are open.

**Allowlist and custom rules.**
- Per-site toggle: an `allowAllRequests` rule on `main_frame` and `sub_frame` for the site, plus uBOL's per-site "no filtering" mode, which skips its content scripts.
- Allowed sites in Settings is the same list.
- Ads and trackers switches map to ruleset groups, toggled with no re-index:
  - Ads: uBlock filters, quick fixes, unbreak, EasyList;
  - Trackers: EasyPrivacy, uBlock privacy.
  - Badware and URLhaus: see §7.

**Effort:** the extension fork (mostly deletions, plus a storage-driven settings layer), a build script for the rulesets, about 400 `//room` lines, and 0–1 patch.

**Rejected variant: pre-install uBOL from the Web Store.** It means a request to Google, Google's update channel and a user-visible extension. That contradicts the first pillar.

## 5. Option (c): an adblock-rust engine linked into `//room`

**How it would work in Room.**
- **The engine.** adblock-rust (MPL-2.0, v0.13.3, about 15k Rust lines) is wrapped in a `cxx` bridge; Brave's is 809 lines.
- **Network blocking** needs our own proxying `URLLoaderFactory`, modelled on `WebRequestProxyingURLLoaderFactory`, which is how Brave's shields work. It is installed from a hook in `ChromeContentBrowserClient::WillCreateURLLoaderFactory`.
- **Cosmetic filtering** needs a renderer `RenderFrameObserver`, a mojom interface and injected JS for selectors, procedural filters and scriptlets (Brave's `components/cosmetic_filters`: 5,593 lines). It is created from a renderer-client hook.

**Network vs cosmetic.**
- **Network:** full ABP/uBO syntax, except `$header`, `$permissions`, `$replace`, `$urlskip` and regex `removeparam` (`abstract_network.rs`, `network.rs:24,74-80`).
- **Cosmetic:** hide selectors and scriptlets. Procedural filters are parsed but run in our injected JS, and some operators are rejected (`cosmetic.rs:978-1025`).
- **The best list compatibility of the three:** uBlock's lists work.

**Compilation and updates.** Text lists are parsed at runtime, so custom lists, custom rules and opt-in updates are just more text. There are no rule-count limits and no re-install.

**Patches and rebase.**
- **+2–3 patches** in two of the busiest files in `//chrome`: the browser client's factory hook, the renderer client's frame hook, and possibly the resource-type plumbing.
- **Crates:** 6–9 to vendor, depending on features: `flatbuffers`, `seahash`, `rustc-hash`, `arrayvec`, `idna`, `percent-encoding`, `thiserror 1.x` (only 2.x is vendored), plus `addr`/`psl` unless we pass Chromium's registry lookup, and `cssparser`/`selectors` for CSS validation.
  - They go into `//third_party/rust`, outside `//room`, whose `Cargo.lock` moved 501 times in a year.
  - Every rustc or shared-crate roll (`regex`, `serde`) can break our crates at a rebase.
  - adblock-rust has 83 `unsafe` sites, so each crate needs `allow_unsafe`.
- **`//room` code:** about 3–5k lines of our own proxy, IPC and injection code. Brave keeps about 40k lines for shields (`components/brave_shields` 24,048, `cosmetic_filters` 5,593, `browser/brave_shields` 10,249) plus 12 patches and 94 `chromium_src` overrides.

**Memory and page load.**
- **Engine memory:** Brave reports a 75 % reduction (45 MB saved) for about 100k default filters after its 2026 FlatBuffers rework (brave.com/privacy-updates/36-adblock-memory-reduction). That puts the engine at about 15 MB, inferred and not stated.
- **Matching:** 4.6–5.7 µs per request (2019 benchmark).
- **Proxying:** the same per-request cost as (b), plus a cosmetic IPC per frame.

**Licences:** MPL-2.0, file-level copyleft and fine for any Room licence. Scriptlet resources would be uBO's (GPLv3) or Brave's `adblock-resources`; the latter's licence lineage is unverified.

**Allowlist and custom rules:** anything; our own code decides.

**Effort:** the largest. It is a subsystem the size of a phase, outside the patch policy's spirit, and it has its own maintenance stream.

## 6. Side by side

| | (a) subresource_filter | (b) DNR extension | (c) adblock-rust |
|---|---|---|---|
| Network blocking | EasyList/EasyPrivacy 99.9 %, uBlock lists ~26–57 %; no SW/shared workers | uBO compiler's coverage; all resource types | Fullest |
| Cosmetic, scriptlets | Ours to write on an unused API; no scriptlets | uBOL's, working today | Ours to write (Brave: 5.6k lines) |
| Default lists | EasyList + EasyPrivacy | uBO's defaults (19k DNR rules) | uBO's defaults |
| Custom lists and rules | Runtime, re-index all | Runtime into dynamic rules (30k cap) | Runtime, no limits |
| Opt-in list updates | Easy | Needs the re-install path (Step 2 spike); releases otherwise | Easy |
| New patches | +2 | 0–1 | +2–3, plus vendored crates |
| Rebase exposure | `//room` on an internal component (79 commits/yr) | 0–1 hook; the extension on web-facing APIs | 2–3 hooks in hot files + Rust crates (Cargo.lock 501/yr) |
| Memory | Lowest (shared mmap) | Rules in the browser; SW idle-terminated | ~15 MB engine (inferred) |
| Page load | ~0 extra; Safe Browsing check on the path | Request proxying (what uBOL users pay now) | Proxying + cosmetic IPC |
| Google in the path | Safe Browsing activation; Google's component suppressed | None | None |
| Licence | BSD + lists | GPL-3.0 extension (public) + lists | MPL-2.0 + resources |
| `//room` size | ~1,000 lines | ~400 lines + the extension fork | ~3–5k lines |

## 7. Recommendation: (b), Room's own fork of uBlock Origin Lite as a hidden built-in extension

**Why (b).**
- It is the only option whose blocking quality is known on day one: the same rulesets and cosmetic engine the user runs in Room today.
- Its Chromium surface is 0–1 hook against a public API Chrome keeps stable for every Web Store extension. That suits a one-person fork whose top risk is rebase cost.
- It needs no Safe Browsing and no Google component.
- The blocker is a public GPL program, which makes the "all open source" pillar literally true.

**Why not (a).** It is cheap in memory, but it cannot run uBlock's lists, cosmetic filtering would be built on an API nobody upstream uses yet, and it activates through Safe Browsing.

**Why not (c).** It is the engine Brave needed 40k lines and 12 patches to host. Its customisation advantage over (b) is real only for very large custom lists and runtime updates, and (b) covers both in its own way.

**What (b) costs, stated plainly.**
- Custom lists share 30,000 dynamic rules: about 8 EasyList-sized lists after uBO's compression.
- Opt-in list updates need the re-install path; until that works, lists update with Room releases.
- Requests go through the browser-process proxy, the same as with uBOL today.

**Decisions for the user:**
1. Approve (b)? If not, (a) is the fallback for "EasyList + EasyPrivacy, network only".
2. If the zero-patch install routes (§4, routes 1 and 2) fail, may Step 2 add the ≤10-line component-DNR hook? Without it, PLAN §4's Chapter 5 no-patch rule stops the work.
3. Where does the GPL extension's source live: this repository (its own top-level directory, e.g. `Blocker/`, published when Room's repository goes public) or a separate public repository now?
4. Peter Lowe's list: drop it (my default), or ask its author for terms?
5. Badware lists (uBlock badware, URLhaus): on with "Block ads", with "Block trackers", or always on as a third row?

## 8. Step 2 outline, after the go-ahead

1. **Spike the install path.** Try route 1, then route 2, then route 3, on a `//room` incremental. Measure:
   - install time;
   - index time for 19k rules;
   - browser-process memory with and without the extension;
   - fixture load time with and without (`scripts/test-servers.sh`).
2. **The Engine API.** `ProfileContentBlocking` on `Profile`, with:
   - categories on/off;
   - the list catalogue with enabled flags;
   - custom lists;
   - custom rules text;
   - allowed sites;
   - blocked count per page.
   
   Plus `FakeContentBlocking` and an `engine-api.md` row.
3. **`//room/core/room_content_blocking.mm`:** the install, `RulesMonitorService` calls, the storage bridge, per-tab counts. ObjC types only across the bridge.
4. **The extension fork.** `scripts/blocker-build.sh` compiles the default rulesets with uBO's `make-rulesets.js`; the fork drops the UI and reads Room's settings from storage.
5. **Settings ▸ Privacy:** Block ads, Block trackers, lists, custom lists, custom rules, allowed sites, "Update lists automatically" (off). Plus the site panel toggle.
6. **Unit tests (CI tier):** site normalisation for the allowlist, list catalogue and category mapping, the custom-list state machine (added, fetching, compiled, failed), and settings persistence.
7. **The `-RoomSpike adblock` tour step** on a local fixture: an ad script, a tracker pixel, a cosmetic `div`, a scriptlet target and an allowed host. Plus a net-log showing 0 requests at launch and idle with updates off.
8. **By-hand steps** for the user, and a progress-log entry.

## Sources

Chromium paths are cited inline at 155.0.8059.36. External sources:
- [uBOL-home](https://github.com/uBlockOrigin/uBOL-home) and its [FAQ](https://github.com/uBlockOrigin/uBOL-home/wiki/Frequently-asked-questions-(FAQ))
- [make-rulesets.js](https://github.com/gorhill/uBlock/blob/master/platform/mv3/make-rulesets.js)
- [adblock-rust](https://github.com/brave/adblock-rust)
- Brave, [adblock memory reduction](https://brave.com/privacy-updates/36-adblock-memory-reduction) (2026-01-05) and [ad-blocker performance](https://brave.com/blog/improved-ad-blocker-performance/) (2019)
- [EasyList licence](https://easylist.to/pages/licence.html)
- [uAssets](https://github.com/uBlockOrigin/uAssets)
- [Peter Lowe's list](https://pgl.yoyo.org/adservers/)
- Chrome's [MV2 deprecation timeline](https://developer.chrome.com/docs/extensions/develop/migrate/mv2-deprecation-timeline)

The list counts in §2.2 come from a classifier run over the 2026-10-17 copies; it mirrors `rule_parser.cc`'s option table and is approximate for edge syntax.
