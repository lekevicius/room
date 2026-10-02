#!/usr/bin/env python3
"""Lists the pure virtuals of BrowserWindow + ui::BaseWindow on the checked-out
Chromium and prints, for each one RoomBrowserWindow does not implement for
real, an override declaration and a stub definition.

Usage: gen_browser_window_stubs.py ~/chromium/src tools/browser_window_real_members.txt
Prints a JSON object {"decls": [...], "defs": [...], "count": N, "real": [...]}.
Re-run after a rebase: a changed signature shows up as a compile error, and
this regenerates the stub file.
"""
import json
import re
import sys

src, real_file = sys.argv[1], sys.argv[2]
real = {l.strip() for l in open(real_file) if l.strip() and not l.startswith('#')}


def pure_virtuals(path, cls):
    text = open(f"{src}/{path}").read()
    body = text[re.search(rf"class (?:\w+\([^)]*\) )?{cls}\b", text).start():]
    # Drop comments.
    body = re.sub(r"//[^\n]*", "", body)
    # Drop members of other platforms: a block that opens with
    # `#if BUILDFLAG(IS_<other>)` and has no #else (asserted).
    for block in re.findall(
            r"#if BUILDFLAG\(IS_(?:ANDROID|CHROMEOS|WIN|LINUX|OZONE)\)\n.*?#endif",
            body, re.S):
        assert "#else" not in block and "#elif" not in block, block
        body = body.replace(block, "")
    out = []
    for m in re.finditer(r"virtual\s+([^;{}]*?)\)\s*(const)?\s*=\s*0\s*;", body, re.S):
        sig = " ".join(m.group(1).split()) + ")"
        const = " const" if m.group(2) else ""
        out.append((sig, const))
    return out


def split(sig):
    # "bool Foo(int a, ...)" -> ("bool", "Foo", "(int a, ...)")
    paren = sig.index("(")
    head = sig[:paren].strip()
    name = head.split()[-1].lstrip("*&")
    ret = head[: head.rindex(name)].strip()
    return ret, name, sig[paren:]


DEFAULTS = {
    "void": "",
    "bool": "  return false;\n",
    "int": "  return 0;\n",
    "std::string": "  return std::string();\n",
    "gfx::Rect": "  return gfx::Rect();\n",
    "gfx::Size": "  return gfx::Size();\n",
    "ui::mojom::WindowShowState": "  return ui::mojom::WindowShowState::kDefault;\n",
    "ui::ZOrderLevel": "  return ui::ZOrderLevel::kNormal;\n",
    "std::vector<StatusBubble*>": "  return {};\n",
    "ShowTranslateBubbleResult": "  return ShowTranslateBubbleResult::kBrowserWindowNotValid;\n",
    "content::KeyboardEventProcessingResult": "  return content::KeyboardEventProcessingResult::NOT_HANDLED;\n",
    "gfx::NativeWindow": "  return gfx::NativeWindow();\n",
}

decls, defs, real_seen = [], [], []
for path, cls in (("ui/base/base_window.h", "BaseWindow"),
                  ("chrome/browser/ui/browser_window.h", "BrowserWindow")):
    for sig, const in pure_virtuals(path, cls):
        ret, name, params = split(sig)
        # Types declared in namespace ui next to ui::BaseWindow are not found
        # by unqualified lookup from RoomBrowserWindow.
        ret = re.sub(r"^ZOrderLevel$", "ui::ZOrderLevel", ret)
        params = re.sub(r"\(ZOrderLevel ", "(ui::ZOrderLevel ", params)
        if name in real:
            real_seen.append(name)
            continue
        if name == "DeleteBrowserWindow":
            continue
        decls.append(f"  {ret} {name}{params}{const} override;")
        # Unnamed-parameter definitions keep -Wunused-parameter quiet.
        body = DEFAULTS.get(ret)
        if body is None:
            if ret.endswith("*") or ret.startswith("std::unique_ptr"):
                body = "  return nullptr;\n"
            else:
                raise SystemExit(f"no default for {ret} {name}")
        defs.append(f"{ret} RoomBrowserWindow::{name}{params}{const} {{\n"
                    f"  RoomStubHit(\"{name}\");\n{body}}}\n")

print(json.dumps({"decls": decls, "defs": defs, "count": len(decls),
                  "real": sorted(real_seen)}, indent=1))
