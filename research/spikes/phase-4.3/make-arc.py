#!/usr/bin/env python3
"""Writes the Arc fixture (Phase 4.3a) by hand from the shape open-source Arc
export tools describe (never from the user's ~/Library/Application Support/Arc):
`StorableSidebar.json` with `sidebar.containers[]`, the second container holding
`spaces` and `items` as arrays that alternate ids and objects (the older shape;
`items` here mixes in a bare object too, as some versions write), spaces with
`id`, `title`, `profile` ({"default": true} or {"custom": {"_0": {"directoryBasename": …}}}),
`containerIDs` (["unpinned", id, "pinned", id]) and `customInfo` (icon, theme colour);
items with `id`, `parentID`, `childrenIds`, `title`, `data` (`tab.savedURL`/`savedTitle`,
`list` for a folder, `itemContainer` for a space's pinned or unpinned root or an
essentials container, `easel` for an unsupported kind); `topAppsContainerIDs`
alternating a profile and the essentials container's id. `User Data/Local State`
names the profiles. Run from this directory."""
import json

def tab(i, parent, url, title):
    data = {"tab": {"savedTitle": title, "timeLastActiveAt": 781_000_000.0}}
    if url is not None:
        data["tab"]["savedURL"] = url
    return {"id": i, "parentID": parent, "childrenIds": [], "title": None, "data": data, "createdAt": 780_000_000.0}

def lst(i, parent, title, children):
    return {"id": i, "parentID": parent, "childrenIds": children, "title": title, "data": {"list": {}}, "createdAt": 780_000_000.0}

def root(i, kind, children):
    return {"id": i, "parentID": None, "childrenIds": children, "title": None, "data": {"itemContainer": {"containerType": kind}}}

def space(i, title, profile, emoji, colour):
    info = {"iconType": {"emoji_v2": emoji}} if emoji else {}
    if colour:
        info["windowTheme"] = {"primaryColorPalette": {"midTone": {"red": colour[0], "green": colour[1], "blue": colour[2], "alpha": 1},
                                                       "shadedTone": {"red": 0.1, "green": 0.1, "blue": 0.1, "alpha": 1}}}
    return {"id": i, "title": title, "profile": profile, "containerIDs": ["unpinned", i + "-U", "pinned", i + "-P"],
            "customInfo": info, "newContainerIDs": [{"unpinned": {}}, i + "-U", {"pinned": {}}, i + "-P"]}

DEFAULT = {"default": True}
WORK = {"custom": {"_0": {"directoryBasename": "Profile 1"}}}
spaces = [
    space("S-HOME", "Home", DEFAULT, "🏠", (0.2, 0.4, 0.8)),
    space("S-WORK", "Work", WORK, "💼", (0.8, 0.3, 0.2)),
    space("S-SIDE", "Side", DEFAULT, None, None),
]
items = [
    root("TA-D", {"topApps": {"_0": {"default": True}}}, ["E1", "E2"]),
    tab("E1", "TA-D", "https://mail.example.com/", "Mail"),
    tab("E2", "TA-D", "https://calendar.example.com/", "Calendar"),
    root("TA-W", {"topApps": {"_0": WORK}}, ["E3"]),
    tab("E3", "TA-W", "https://chat.work.example/", "Chat"),
    root("S-HOME-P", {"spaceItems": {"_0": "S-HOME"}}, ["T1", "F1", "X1"]),
    tab("T1", "S-HOME-P", "https://news.example.com/", "News"),
    lst("F1", "S-HOME-P", "Projects", ["T2", "F2", "T2b"]),
    tab("T2", "F1", "https://projects.example/room", "Room project"),
    lst("F2", "F1", "Nested", ["T3"]),
    tab("T3", "F2", "https://projects.example/nested", "Nested page"),
    tab("T2b", "F1", "https://projects.example/room#top", "Room project again"),
    {"id": "X1", "parentID": "S-HOME-P", "childrenIds": [], "title": "A canvas", "data": {"easel": {"easelID": "e1"}}},
    root("S-HOME-U", {"spaceItems": {"_0": "S-HOME"}}, ["T5", "T6", "T6b"]),
    tab("T5", "S-HOME-U", "http://127.0.0.1:8780/alpha.html", "Import fixture Alpha"),
    tab("T6", "S-HOME-U", "https://search.example/?q=room", "Search"),
    tab("T6b", "S-HOME-U", None, "A tab without a URL"),
    root("S-WORK-P", {"spaceItems": {"_0": "S-WORK"}}, ["T7"]),
    tab("T7", "S-WORK-P", "https://tracker.work.example/", "Tracker"),
    root("S-WORK-U", {"spaceItems": {"_0": "S-WORK"}}, ["T8"]),
    tab("T8", "S-WORK-U", "https://docs.work.example/spec", "Spec"),
    root("S-SIDE-P", {"spaceItems": {"_0": "S-SIDE"}}, ["T9"]),
    tab("T9", "S-SIDE-P", "https://news.example.com/", "News in Side"),
    root("S-SIDE-U", {"spaceItems": {"_0": "S-SIDE"}}, []),
]
def alternate(objects):
    out = []
    for o in objects:
        out += [o["id"], o]
    return out
item_array = alternate(items[:-1]) + [items[-1]]  # the last one as a bare object
doc = {"sidebar": {"containers": [{"global": {}},
                                  {"spaces": alternate(spaces), "items": item_array,
                                   "topAppsContainerIDs": [DEFAULT, "TA-D", WORK, "TA-W"]}]},
       "sidebarSyncState": {"spaceModels": []}, "version": 1}
with open("arc/StorableSidebar.json", "w") as f:
    json.dump(doc, f, indent=2, ensure_ascii=False)
    f.write("\n")
with open("arc/User Data/Local State", "w") as f:
    json.dump({"profile": {"info_cache": {"Default": {"name": "Personal"}, "Profile 1": {"name": "Work"}}}}, f, indent=2)
    f.write("\n")
print("arc/StorableSidebar.json arc/User Data/Local State")
