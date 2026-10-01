# Build log

Measured timings on the dev machine: Apple M1 Max (10 cores), 64 GB RAM, macOS 27.0.1, Xcode 27.0 (27A266a), CMake from Homebrew. Wall-clock seconds unless noted. Network: home connection, CDN downloads ~60–90 MB/s.

## CEF (scaffold engine)

`scripts/bootstrap-cef.sh`, CEF `154.0.32+g682c378+chromium-154.0.8037.58`, macOS arm64, `api_version=15400`.

| Date | Step | Time | Notes |
|---|---|---|---|
| 2026-10-01 | Download minimal (132.2 MB) | 2 s | SHA-1 matches pin and CDN index |
| 2026-10-01 | Download standard (307.0 MB), for `tests/` only | 15 s | minimal ships no `tests/`; cefsimple sources taken from standard |
| 2026-10-01 | Extract minimal | 9 s | framework 322 MB on disk, main dylib 233.8 MB |
| 2026-10-01 | Extract `tests/` from standard | 18 s | |
| 2026-10-01 | CMake configure (Unix Makefiles, Release) | 5 s | |
| 2026-10-01 | Build `libcef_dll_wrapper` (-j10) | 24 s | 5.6 MB `.a`, C++20, `-fobjc-arc` |
| 2026-10-01 | Build `cefsimple` | 127 s | validates Xcode 27 toolchain |
| 2026-10-01 | Run `cefsimple` 8 s, quit via AppleEvent | quit < 1 s, exit 0 | 5 helper processes while running |
| 2026-10-01 | Whole script, cold | 201 s | |
