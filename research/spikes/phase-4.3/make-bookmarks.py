#!/usr/bin/env python3
"""Writes the Chrome-family `Bookmarks` fixtures (Phase 4.3a) in the format
components/bookmarks/browser/bookmark_codec.cc defines: `roots.bookmark_bar`,
`other`, `synced`; nodes with `type` url|folder, `name`, `url`, `children`,
`date_added` (WebKit microseconds, decimal strings), `guid`, `id`. Every node
is listed below; nothing comes from a real profile. Run from this directory."""
import json, uuid

next_id = 4
BASE = 13_400_000_000_000_000  # 2025-08-11 in WebKit microseconds (since 1601)


def guid(name):
    return str(uuid.uuid5(uuid.NAMESPACE_URL, "room-4.3/" + name))


def url(name, href, offset=0):
    global next_id
    next_id += 1
    return {"date_added": str(BASE + offset * 1_000_000), "date_last_used": "0", "guid": guid(name + href),
            "id": str(next_id), "meta_info": {}, "name": name, "type": "url", "url": href}


def folder(name, children, offset=0):
    global next_id
    next_id += 1
    return {"children": children, "date_added": str(BASE + offset * 1_000_000), "date_last_used": "0",
            "date_modified": str(BASE + offset * 1_000_000), "guid": guid("folder/" + name), "id": str(next_id),
            "name": name, "type": "folder"}


def root(rid, name, g, children):
    return {"children": children, "date_added": str(BASE), "date_last_used": "0", "date_modified": str(BASE),
            "guid": g, "id": rid, "name": name, "type": "folder"}


def chrome():
    # The bar: 14 links (more than the Essentials cap, 12), a folder six levels deep (the depth clip at 5),
    # a folder with a duplicate of the first link (by normalised URL: "www." and the fragment dropped),
    # and a bookmarklet (javascript:, skipped).
    bar = [url("Room Docs", "https://example.org/docs", 1), url("Alpha", "http://127.0.0.1:8780/alpha.html", 2)]
    bar += [url(f"Site {n}", f"https://site{n}.example/", 2 + n) for n in range(1, 13)]
    deep = folder("L6", [url("Six", "https://deep.example/six"), folder("L7", [url("Seven", "https://deep.example/seven")])])
    for level in (5, 4, 3, 2, 1):
        deep = folder(f"L{level}", [url(f"Level {level}", f"https://deep.example/{level}"), deep])
    bar += [folder("Work", [url("Tracker", "https://tracker.example.com/"), url("Docs again", "https://www.example.org/docs#intro")]),
            deep, url("Bookmarklet", "javascript:alert(1)")]
    other = [url("Beta", "http://127.0.0.1:8780/beta.html", 30),
             folder("Reading", [url("Article A", "https://news.example.com/a"), url("Article B", "https://news.example.com/b")], 31),
             url("Alpha again", "http://127.0.0.1:8780/alpha.html", 32),
             url("Example", "https://example.com:443/", 33)]
    synced = [url("Mobile", "https://m.example.com/", 40), url("Example on the phone", "HTTPS://WWW.Example.com", 41)]
    return {"checksum": "", "roots": {
        "bookmark_bar": root("1", "Bookmarks bar", "0bc5d13f-2cba-5d74-951f-3f233fe6c908", bar),
        "other": root("2", "Other bookmarks", "82b081ec-3dd3-529c-8475-ab6c344590dd", other),
        "synced": root("3", "Mobile bookmarks", "4cf2e351-0e85-532b-bb37-df045d8f8d0f", synced)}, "version": 1}


def profile1():
    return {"checksum": "", "roots": {
        "bookmark_bar": root("1", "Bookmarks bar", "0bc5d13f-2cba-5d74-951f-3f233fe6c908", [url("Work home", "https://work.example/")]),
        "other": root("2", "Other bookmarks", "82b081ec-3dd3-529c-8475-ab6c344590dd", []),
        "synced": root("3", "Mobile bookmarks", "4cf2e351-0e85-532b-bb37-df045d8f8d0f", [])}, "version": 1}


for path, value in (("chrome/Default/Bookmarks", chrome()), ("chrome/Profile 1/Bookmarks", profile1())):
    with open(path, "w") as f:
        json.dump(value, f, indent=3, ensure_ascii=False)
        f.write("\n")
    print(path)
