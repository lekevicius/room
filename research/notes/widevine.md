# Widevine on the signed build (B-101) — 2026-10-18

Netflix refused to play in the signed Room (build 13, `/Applications/Room.app`,
155.0.8059.36) and pointed at `chrome://settings/content/protectedContent`,
which is on. Two causes, one under the other:

1. **The CDM never loads** in a Developer ID build: macOS library validation
   refuses Google's `libwidevinecdm.dylib` in Room's helper. Measured below,
   fixed by one entitlement in the signing script, no Chromium build.
2. **No Verified Media Path (VMP) signature.** Once the CDM loads, Room is
   still an unverified platform to Widevine's license servers; Netflix (and
   probably other premium services) refuses licences to unverified macOS and
   Windows clients. Fixing that needs a VMP signing certificate (Google or
   castlabs' 3PL programme), a GN arg, a small `//room` change and a signing
   step. Not measured here: no certificate.

## 1. The CDM installs and registers, then fails to load

**Install.** The engine's data root (`~/Library/Application Support/Room/RoomCore`)
has `WidevineCdm/4.10.3112.0/_platform_specific/mac_arm64/libwidevinecdm.dylib`
(20,416,896 bytes, plus its `.sig`), written 2026-10-11 20:05 by `//room`'s
demand hook (patch 0007). The CDM is signed by Google
(`TeamIdentifier=EQHXZ8M8AV`). The older `Room/Engine/WidevineCdm/4.10.3050.0`
is the CEF engine's root, unused since 3.9.

**Registration.** It works: the browser handed the CDM's path to the CDM
service process, which tried to load it (below). `Local State` keeps no
Widevine entry; the component is registered from the directory at demand time.

**Load: fails.** The running Room's log (`RoomCore/RoomCore.log`, 911,180 lines
since 2026-10-08) has exactly one CDM load attempt in ten days, the user's
Netflix visit at 21:20:21:

```
[17719:…:1018/212021.870907:ERROR:media/cdm/cdm_module.cc:126] CDM at …/RoomCore/WidevineCdm/4.10.3112.0/_platform_specific/mac_arm64/libwidevinecdm.dylib could not be loaded.
[17719:…:1018/212021.871208:ERROR:media/cdm/cdm_module.cc:127] Error: dlopen(…libwidevinecdm.dylib, 0x0005): tried: '…libwidevinecdm.dylib' (code signature in <4C4C44E6-5555-3144-A103-758AAE0E7592> '…libwidevinecdm.dylib' not valid for use in process: mapping process and mapped file (non-platform) have different Team IDs), …
[42536:…:1018/212021.873500:INFO:CONSOLE:0] "Uncaught (in promise) [object Object]", source: https://www.netflix.com/browse (0)
```

Then Netflix's watch page tried to open `chrome://settings/content/protectedContent`
three times (21:20:30, 21:20:34, 21:21:11; "Not allowed to load local
resource"). That is the message the user saw: Netflix's generic "Widevine is
unavailable" advice, not a setting.

**Why.** Room's helpers are signed with the hardened runtime
(`flags=0x10000(runtime)`, Team N56PMJ99UT). The hardened runtime enforces
library validation unless a process has
`com.apple.security.cs.disable-library-validation`: a non-Apple dylib must be
signed by the process's own team. Chrome passes because Chrome and the CDM are
both Google's (EQHXZ8M8AV). Room's base and Aperitif helpers get
`Helper.entitlements` (empty), so the CDM process cannot map a Google-signed
library.

**Why 2026-10-03's verification missed it.** The probe (`roomcore-features.sh
widevine`, "Demand-only Widevine provisioning" in
`roomcore-network-audit.md`) ran the Debug host, which is ad-hoc signed
(`flags=0x2(adhoc)`, no Team ID, no hardened runtime), so no library validation
applied. The release build has no `-RoomSpike` hooks (`room_enable_spikes`
unset), and the signed DMG was never probed for EME.

### The probe on signed copies (this session)

The Debug host (RoomCore 155.0.8059.36, built 2026-10-07) cloned and signed by
`scripts/roomcore-sign.sh --no-notarize` (Developer ID, hardened runtime,
today's entitlements; 31.2 s), then copies re-signed with
`disable-library-validation` on chosen helpers. Each run is
`scripts/roomcore-features.sh widevine` (loopback fixture, EME
`requestMediaKeySystemAccess` + `createMediaKeys`), with the profile seeded with
a copy of the installed CDM 4.10.3112.0, so nothing was downloaded. Load
average was 580–690 because the laptop's official build 14 was compiling.

| Signed copy | Helpers with `disable-library-validation` | EME result | Time | Team ID `dlopen` errors |
|---|---|---|---|---|
| as shipped | none | NotSupportedError "CreateCdmFunc not available." | 4.862 s | 1 |
| base | `Room Helper.app` | NotSupportedError "CreateCdmFunc not available." | 3.719 s | 1 |
| aperitif | `Room Helper (Aperitif).app` | **MediaKeys created** | 3.694 s | 0 |
| both | `Room Helper.app`, `Room Helper (Aperitif).app` | **MediaKeys created** | 3.134 s | 0 |

All four runs ended through the teardown watchdog (exit status 2, the same
with and without the fix; the load, not the CDM). The NetLogs of the "as
shipped" and "both" runs hold 14 loopback events and **0 external hosts**.
Evidence stayed in the session's scratch directory (signed apps, NetLogs, host
logs), not in the repository.

So in 155 the CDM's utility process starts from the Aperitif helper; the base
helper alone does not help. `ROOM_BASE_HELPER_ENTITLEMENTS` (the existing
experiment hook in `sign-and-notarize.sh`) covers only the base helper, so it
cannot fix this without a script change.

### What the other Chromium browsers on this Mac do

`codesign -d` on the installed apps (2026-10-18):

| Browser (Team) | Base / Aperitif helper | Framework VMP signature |
|---|---|---|
| Google Chrome 155 (EQHXZ8M8AV) | library validation **on** (`0x12a00`); same team as the CDM | `Google Chrome Framework.sig` |
| Microsoft Edge 155 (UBF8T346G9) | library validation on; ships its own `Libraries/WidevineCdm` re-signed with Microsoft's Team ID | `Microsoft Edge Framework.sig` |
| Arc (S6N382Y83G) | `disable-library-validation` on both | `ArcCore.sig` |
| Dia (S6N382Y83G) | `disable-library-validation` on both | `ArcCore.sig` |
| Brave 154 (KL8N8XSYF4) | `disable-library-validation` on both | `Brave Browser Framework.sig` |
| Vivaldi 8.1 (4XF3XNRN6Y) | `disable-library-validation` on the base helper | `Vivaldi Framework.sig` |
| Opera 133 (A2P9LX4JPN) | `disable-library-validation` on the base and Plugin helpers | `Opera Framework.sig` |
| Comet 145 (7S8W4W365S) | `disable-library-validation` on the base and Plugin helpers | `Comet Framework.sig` |
| **Room** (N56PMJ99UT) | none | **none** |

Every Chromium browser on the machine that downloads Google's CDM disables
library validation on the helper that hosts it; renderers and GPU keep
`allow-jit` only. Brave, Arc and Vivaldi pass Gatekeeper as "Notarized
Developer ID" with it, so it does not block notarization. castlabs' FAQ asks
the same of Electron apps: on macOS 10.15 and later the
`disable-library-validation` entitlement is needed to load the Widevine CDM.

**Cost of the entitlement.** The Aperitif helper hosts more than the CDM: the
running Room has its GPU process and its network, storage, audio and
video-capture services there (`ps`, 2026-10-18; renderers run from
`Room Helper (Aperitif Renderer)`). All of them could then load dylibs signed
by any Developer ID team. `DYLD_*` injection stays blocked (no
`allow-dyld-environment-variables`); a dylib still has to be on disk and
asked for. Renderers keep library validation. Arc, Dia and Brave accept the
same trade on the same helpers. Edge's alternative,
re-signing the CDM with our own Team ID, would mean shipping the CDM in the
bundle: Google's terms allow that only to licensees, and Room fetches it on
demand.

## 2. VMP: what Netflix and Spotify need

**What it is.** Widevine on macOS and Windows checks the integrity of the
binaries hosting the CDM: the host passes the CDM a list of `(file, file.sig)`
pairs, where each `.sig` was made with a VMP certificate Widevine trusts. The
license server learns the result: `PLATFORM_UNVERIFIED`, `PLATFORM_TAMPERED`,
`PLATFORM_SOFTWARE_VERIFIED`, … (castlabs' VMP wiki). Linux has no VMP.

**Chrome's mechanism, and why Room has none of it.**

- `enable_cdm_host_verification` (`media/media_options.gni`) defaults to
  `is_chrome_branded` on Mac/Windows. Room's `args/release.gn` does not set it,
  so the verification code is not compiled.
- `AddCdmHostFilePaths` (`chrome/common/media/cdm_host_file_path.cc`) is
  implemented only under `GOOGLE_CHROME_BRANDING`: on Mac it lists
  `<Framework>.framework/Versions/X/<Framework>` with its signature at
  `…/Versions/X/Resources/<Framework>.sig`. The unbranded branch is
  `NOTIMPLEMENTED()` ("CDM host file paths need to be provided…").
- The `.sig` is produced by `//third_party/widevine/scripts/signature_generator.py`
  (`widevine_sign_file`, flag 1 for the framework, `chrome/BUILD.gn`). In the
  public checkout that directory is **empty**: the script and certificate come
  only with a Widevine agreement.

Every shipping browser above has the framework `.sig`; Room has none.

**What services do with an unverified client.**

- castlabs' VMP wiki: on macOS and Windows, `PLATFORM_UNVERIFIED` means
  "production streaming services will typically not work"; Bitmovin and
  Intertrust say Widevine's license servers by default issue licences only to
  VMP-capable CDMs.
- Netflix: the help page for M7701-1003 says a Chromium-based browser other
  than Chrome is "not supported by Netflix". In castlabs' issue #224 (March
  2026) a VMP-signed build that showed M7121-1331 played Netflix once it was
  "properly VMP-signed", per the maintainer. So expect Netflix to fail on Room
  even with the CDM loading, until Room is VMP-signed.
- Spotify Web: no primary source found. User reports (chromiumbuilds#6,
  Spotify community threads) say playback "is not guaranteed" without the
  `.sig` file. Spotify is a cheaper test than Netflix: try it once the CDM loads.

**How a fork gets VMP.**

| Route | What it gives | Cost |
|---|---|---|
| Google Widevine, direct | A VMP certificate and `signature_generator.py`, as Brave, Vivaldi, Opera and Arc have | Free (PLAN §4: "free but gated"): a licence agreement Google must accept; turnaround unknown, not guaranteed for a one-person project |
| castlabs 3PL ("Widevine certification") | castlabs audits the app's CDM integration (a Google-authorised Third Party Lab), then signs | Commercial, "low-cost", no public price; contact castlabs |
| castlabs EVS | Free self-service VMP signing | **Not available to Room**: EVS signs only castlabs' Electron (ECS) builds; custom Chromium builds go through 3PL |

**What Room would change, with a certificate in hand.**

1. `args/release.gn`: `enable_cdm_host_verification = true` (allowed on Mac;
   the GN assert only excludes Chrome for Testing).
2. Host file paths for the unbranded build: `RoomCore.framework/Versions/X/RoomCore`
   and `Resources/RoomCore.sig`. Either a `chromium_src` shadow of
   `cdm_host_file_path.cc` or a `//room` provider plus a one-line hook. A
   Chapter 5 engine change (no-patch rule: prefer the shadow), then a release
   rebuild (~4 h 43 min clean on the Mac mini, or the ~8 min incremental if
   only `//room` changes).
3. A signing step in `scripts/sign-and-notarize.sh`: generate `RoomCore.sig`
   over the framework binary **before** Apple codesigning (castlabs: on macOS
   VMP signing comes first), every build, since the binary changes.

## 3. Proposed fix

**Now (no Chromium build, no account; applied 2026-10-18 at the user's go-ahead, verified: a Debug host clone signed by the changed script gets the entitlement on exactly those two helpers and creates MediaKeys in 3.706 s, 0 Team ID errors; build 14 is the first DMG signed with it):** a `Helper-CDM.entitlements`
(`com.apple.security.cs.disable-library-validation`) in `App/Resources`, given by
`sign-and-notarize.sh` to `Room Helper (Aperitif).app` and `Room Helper.app`
(the base helper as Arc, Dia and Brave do, in case a configuration launches
utilities from it). Cost: two lines in the helper `case`, one plist, the
entitlement's weaker library check on utility processes, and PLAN §4's
Entitlements row updated. The next signed DMG then loads the CDM; whether
Netflix and Spotify play is then the VMP question, answered by the by-hand
steps below.

**For Netflix (if the by-hand steps show the VMP refusal):** apply to Google
for a Widevine VMP certificate (the user: an account only the user can hold),
or ask castlabs for a 3PL quote. Then the three changes above. Until then the
first release says "DRM video: some services (Netflix) do not support Room yet".

## 4. By-hand steps for the user

1. **Now, build 13 (as shipped):** open `chrome://components` in Room and note
   the Widevine Content Decryption Module row (expected 4.10.3112.0). Open a
   Netflix title and write down the error code on Netflix's error page (the
   `M7xxx-xxxx` code, e.g. M7701-1003); a screenshot is fine.
2. **On the first DMG signed with the entitlement fix:** the same Netflix title.
   Write down whether it plays and the error code if not (M7121-1331, or a new
   one, points at VMP).
3. Same build: `open.spotify.com`, play any track. Plays / error text.
4. Same build: the Shaka Player demo
   (`shaka-player-demo.appspot.com`, "Angel One (multicodec, multilingual,
   Widevine)"). It uses a test license server, so it should play with the CDM
   loaded even without VMP. It separates "CDM works" from "service refuses".
5. Optional, for comparison: the Netflix title in Google Chrome on the same
   Mac (should play).

## Side note

The same Netflix session logged 304 `ssl_client_socket_impl` handshake
failures (−107) and Netflix's client logging failing ("There was an error
sending the data to CL"). That is the local DNS sinkhole on the laptop
answering blocked hosts with `[::]:443` (B-3, `roomcore-tls-audit.md`), not
Room, and it is unrelated to DRM.

## Sources

- castlabs, EVS wiki: <https://github.com/castlabs/electron-releases/wiki/EVS>
- castlabs, VMP wiki: <https://github.com/castlabs/electron-releases/wiki/VMP>
- castlabs, FAQ (macOS `disable-library-validation`): <https://github.com/castlabs/electron-releases/wiki/FAQ>
- castlabs, issue #224 (Netflix M7121-1331, works once VMP-signed): <https://github.com/castlabs/electron-releases/issues/224>
- castlabs, Widevine certification and 3PL: <https://castlabs.com/security/widevine-certification/>
- Bitmovin / Intertrust on VMP enforcement: <https://bitmovin.com/blog/how-to-trust-your-player-building-an-ott-service-for-todays-world-p2/>
- Netflix, error M7701-1003: <https://help.netflix.com/en/node/27451>
- chromiumbuilds#6 (Spotify and Netflix without the `.sig`): <https://github.com/AmirAgassi/chromiumbuilds/issues/6>
- Chromium 155 checkout: `media/media_options.gni`, `third_party/widevine/cdm/widevine.gni`,
  `chrome/common/media/cdm_host_file_path.cc`, `chrome/BUILD.gn`,
  `chrome/installer/mac/signing/parts.py`, `content/public/browser/child_process_host.h`
