#!/usr/bin/env python3
"""Generates //room/third_party/rust/<crate>/v<epoch>/BUILD.gn for every crate
that room/third_party/rust/Cargo.lock resolves (cargo_crate targets, as
Chromium's gnrt does for //third_party/rust).

Room cannot use Chromium's vendored crates: most are visible only to
//third_party/rust and several lack the features adblock-rust needs. Room's
crates are vendored into room/third_party/rust/vendor/ (gitignored) by
Engine/roomcore/tools/vendor_rust_crates.sh, which runs this script.

Every crate gets an explicit rustc_metadata ("room_<name>-<epoch>") so its
symbols never collide with Chromium's copy of the same crate in one binary,
and the target is "room_lib" (not gnrt's "lib") because cargo_crate names
build-script executables after crate, target and epoch in one directory.

Usage: gen_rust_crates.py <room/third_party/rust directory>
"""

import json
import os
import re
import subprocess
import sys

TARGET = "aarch64-apple-darwin"
ROOT_LABEL = "//room/third_party/rust"
# Build scripts that only turn on nightly features when rustc is a nightly
# (Chromium's is, but it allows no unstable features): dropped, as gnrt's
# config drops them for Chromium's own crates.
REMOVE_BUILD_RS = {"flatbuffers"}
SKIP_DIRS = {"tests", "benches", "examples", "fuzz", "target", ".github"}


def epoch(version):
    parts = version.split("-")[0].split(".")
    out = []
    for part in parts:
        out.append(part)
        if part != "0":
            break
    return ".".join(out)


def gn_string(value):
    value = value.replace("\\", "\\\\").replace('"', '\\"').replace("$", "\\$")
    return '"' + " ".join(value.split()) + '"'


def gn_list(values, indent="  "):
    if not values:
        return "[]"
    if len(values) == 1:
        return "[ " + gn_string(values[0]) + " ]"
    body = "".join(f"{indent}  {gn_string(v)},\n" for v in values)
    return "[\n" + body + indent + "]"


def crate_files(crate_dir):
    rs, other = [], []
    for root, dirs, files in os.walk(crate_dir):
        dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS and not d.startswith("."))
        for name in sorted(files):
            path = os.path.join(root, name)
            if name.endswith(".rs"):
                rs.append(path)
            elif os.path.relpath(root, crate_dir).split(os.sep)[0] == "src":
                other.append(path)
    return rs, other


def main():
    rust_dir = os.path.abspath(sys.argv[1])
    vendor = os.path.join(rust_dir, "vendor")
    meta = json.loads(subprocess.check_output(
        ["cargo", "metadata", "--format-version", "1", "--locked", "--offline",
         "--filter-platform", TARGET,
         "--manifest-path", os.path.join(rust_dir, "Cargo.toml")],
        env=dict(os.environ, CARGO_NET_OFFLINE="true")))
    packages = {p["id"]: p for p in meta["packages"]}
    nodes = {n["id"]: n for n in meta["resolve"]["nodes"]}
    root_id = meta["resolve"]["root"]

    def lib_target(pkg):
        for target in pkg["targets"]:
            if set(target["kind"]) & {"lib", "rlib", "proc-macro"}:
                return target
        return None

    def label(pkg):
        return f"{ROOT_LABEL}/{pkg['name'].replace('-', '_')}/v{epoch(pkg['version']).replace('.', '_')}:room_lib"

    def gn_path(path, crate_dir, vendored):
        return "//room/third_party/rust/vendor/" + vendored + "/" + os.path.relpath(path, crate_dir)

    written = []
    for pkg_id, node in sorted(nodes.items()):
        if pkg_id == root_id:
            continue
        pkg = packages[pkg_id]
        lib = lib_target(pkg)
        vendored = f"{pkg['name']}-{pkg['version']}"
        crate_dir = os.path.join(vendor, vendored)
        if not os.path.isdir(crate_dir):
            sys.exit(f"missing vendored crate {crate_dir}; run vendor_rust_crates.sh")
        src_dir = os.path.dirname(pkg["manifest_path"])
        crate_root = os.path.join(crate_dir, os.path.relpath(lib["src_path"], src_dir))
        rs, other = crate_files(crate_dir)
        build = next((t for t in pkg["targets"] if "custom-build" in t["kind"]), None)
        if pkg["name"] in REMOVE_BUILD_RS:
            build = None
        build_root = None
        if build:
            build_root = os.path.join(crate_dir, os.path.relpath(build["src_path"], src_dir))
            rs = [f for f in rs if f != build_root]

        deps, build_deps, aliased = [], [], {}
        for dep in node["deps"]:
            dep_pkg = packages[dep["pkg"]]
            dep_lib = lib_target(dep_pkg)
            kinds = {k["kind"] for k in dep["dep_kinds"]}
            dep_label = label(dep_pkg)
            if None in kinds:
                deps.append(dep_label)
                if dep["name"] != dep_lib["name"].replace("-", "_"):
                    aliased[dep["name"]] = dep_label
            if "build" in kinds and pkg["name"] not in REMOVE_BUILD_RS:
                build_deps.append(dep_label)

        crate_type = "proc-macro" if "proc-macro" in lib["kind"] else "rlib"
        name = lib["name"].replace("-", "_")
        ep = epoch(pkg["version"])
        if build_root and os.path.isdir(os.path.join(crate_dir, "build")):
            build_dir = os.path.join(crate_dir, "build") + os.sep
            rs = [f for f in rs if not f.startswith(build_dir)]
        out = [
            "# Generated by Engine/roomcore/tools/gen_rust_crates.py from",
            "# room/third_party/rust/Cargo.lock. Do not edit.",
            "",
            'import("//build/rust/cargo_crate.gni")',
            "",
            'cargo_crate("room_lib") {',
            f"  crate_name = {gn_string(name)}",
            f"  epoch = {gn_string(ep)}",
            f"  crate_type = {gn_string(crate_type)}",
            f"  crate_root = {gn_string(gn_path(crate_root, crate_dir, vendored))}",
            f"  sources = {gn_list([gn_path(f, crate_dir, vendored) for f in rs])}",
            f"  inputs = {gn_list([gn_path(f, crate_dir, vendored) for f in other])}",
            "  build_native_rust_unit_tests = false",
            f"  edition = {gn_string(lib.get('edition') or pkg['edition'])}",
            f"  cargo_pkg_authors = {gn_string(', '.join(pkg.get('authors') or []))}",
            f"  cargo_pkg_name = {gn_string(pkg['name'])}",
            f"  cargo_pkg_description = {gn_string(pkg.get('description') or '')}",
            f"  cargo_pkg_repository = {gn_string(pkg.get('repository') or '')}",
            f"  cargo_pkg_version = {gn_string(pkg['version'])}",
            f"  rustc_metadata = {gn_string('room_' + name + '-' + ep)}",
            "  allow_unsafe = true",
            f"  deps = {gn_list(sorted(deps))}",
        ]
        if aliased:
            out.append("  aliased_deps = {")
            out += [f"    {k} = {gn_string(v)}" for k, v in sorted(aliased.items())]
            out.append("  }")
        if node["features"]:  # run_build_script.py refuses an empty --features
            out.append(f"  features = {gn_list(sorted(node['features']))}")
        if build_root:
            # Files the script writes to OUT_DIR that the crate include!s
            # (serde's private.rs); gnrt keeps these in its config.
            with open(build_root) as f:
                outputs = sorted({m for line in f if "out_dir" in line.lower()
                                  for m in re.findall(r'join\("([\w.]+\.rs)"\)', line)})
            # Files the script reads from the crate (thiserror's build/probe.rs).
            extra = [os.path.join(crate_dir, "build", n)
                     for n in sorted(os.listdir(os.path.join(crate_dir, "build")))] \
                if os.path.isdir(os.path.join(crate_dir, "build")) else []
            rs = [f for f in rs if f not in extra]
            out.append(f"  build_root = {gn_string(gn_path(build_root, crate_dir, vendored))}")
            out.append(f"  build_sources = {gn_list([gn_path(f, crate_dir, vendored) for f in [build_root] + extra])}")
            if outputs:
                out.append(f"  build_script_outputs = {gn_list(outputs)}")
            out.append(f"  build_deps = {gn_list(sorted(build_deps))}")
        out += [
            "",
            "  # Third-party code: no chromium_code warnings, no coverage.",
            "  _configs_to_remove = [",
            '    "//build/config/coverage:default_coverage",',
            '    "//build/config/compiler:chromium_code",',
            "  ]",
            "  library_configs -= _configs_to_remove",
            "  executable_configs -= _configs_to_remove",
            "  proc_macro_configs -= _configs_to_remove",
            "}",
            "",
        ]
        gn_dir = os.path.join(rust_dir, name, "v" + ep.replace(".", "_"))
        os.makedirs(gn_dir, exist_ok=True)
        with open(os.path.join(gn_dir, "BUILD.gn"), "w") as f:
            f.write("\n".join(out))
        written.append(os.path.relpath(gn_dir, rust_dir))
    print(f"{len(written)} crates: " + " ".join(sorted(written)))


if __name__ == "__main__":
    main()
