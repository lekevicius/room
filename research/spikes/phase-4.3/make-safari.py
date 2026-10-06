#!/usr/bin/env python3
"""Writes the Safari fixtures (Phase 4.3a) from the formats, never from ~/Library/Safari:
`Bookmarks.plist` (a root WebBookmarkTypeList whose Children are WebBookmarkTypeList
folders ("BookmarksBar", "BookmarksMenu", "com.apple.ReadingList", user folders),
WebBookmarkTypeLeaf links (URLString, URIDictionary.title) and a WebBookmarkTypeProxy
(History)), converted to a binary plist with plutil as Safari writes it; and `History.db`
(history_items, history_visits; visit_time in seconds since 2001-01-01). Run from this directory."""
import os, plistlib, sqlite3, subprocess, uuid


def uid(name):
    return str(uuid.uuid5(uuid.NAMESPACE_URL, "room-4.3/safari/" + name)).upper()


def leaf(title, href, reading=False):
    node = {"WebBookmarkType": "WebBookmarkTypeLeaf", "URLString": href, "URIDictionary": {"title": title},
            "WebBookmarkUUID": uid(title + href)}
    if reading:
        node["ReadingList"] = {"DateAdded": __import__("datetime").datetime(2026, 9, 1), "PreviewText": "An article."}
    return node


def folder(title, children):
    return {"WebBookmarkType": "WebBookmarkTypeList", "Title": title, "Children": children, "WebBookmarkUUID": uid("folder/" + title)}


root = {
    "WebBookmarkType": "WebBookmarkTypeList", "Title": "", "WebBookmarkFileVersion": 1, "WebBookmarkUUID": uid("root"),
    "Children": [
        {"WebBookmarkType": "WebBookmarkTypeProxy", "Title": "History", "WebBookmarkIdentifier": "History",
         "WebBookmarkUUID": uid("history")},
        folder("BookmarksBar", [leaf("Apple", "https://www.apple.com/"), leaf("Alpha", "http://127.0.0.1:8780/alpha.html"),
                                folder("Dev", [leaf("GitHub", "https://github.com/"), leaf("Swift", "https://swift.org/"),
                                               leaf("Swift again", "https://www.swift.org")])]),
        folder("BookmarksMenu", [leaf("Wikipedia", "https://www.wikipedia.org/"),
                                 folder("Recipes", [leaf("Soup", "https://recipes.example/soup")])]),
        folder("com.apple.ReadingList", [leaf("Article A", "https://news.example.com/a", reading=True),
                                         leaf("Article C", "https://news.example.com/c", reading=True)]),
        folder("Travel", [leaf("Maps", "https://maps.example/"), {"WebBookmarkType": "WebBookmarkTypeLeaf",
                                                                   "URIDictionary": {"title": "No URL"}, "WebBookmarkUUID": uid("nourl")}]),
    ],
}
with open("safari/Bookmarks.plist", "wb") as f:
    plistlib.dump(root, f, fmt=plistlib.FMT_XML)
subprocess.run(["plutil", "-convert", "binary1", "safari/Bookmarks.plist"], check=True)

if os.path.exists("safari/History.db"):
    os.remove("safari/History.db")
db = sqlite3.connect("safari/History.db")
db.executescript("""
CREATE TABLE history_items (id INTEGER PRIMARY KEY AUTOINCREMENT, url TEXT NOT NULL UNIQUE, domain_expansion TEXT NULL,
  visit_count INTEGER NOT NULL, daily_visit_counts BLOB NOT NULL, weekly_visit_counts BLOB NULL, autocomplete_triggers BLOB NULL,
  should_recompute_derived_visit_counts INTEGER NOT NULL, visit_count_score INTEGER NOT NULL, status_code INTEGER NOT NULL DEFAULT 0);
CREATE TABLE history_visits (id INTEGER PRIMARY KEY AUTOINCREMENT, history_item INTEGER NOT NULL REFERENCES history_items(id) ON DELETE CASCADE,
  visit_time REAL NOT NULL, title TEXT NULL, load_successful BOOLEAN NOT NULL DEFAULT 1, http_non_get BOOLEAN NOT NULL DEFAULT 0,
  synthesized BOOLEAN NOT NULL DEFAULT 0, redirect_source INTEGER NULL UNIQUE REFERENCES history_visits(id) ON DELETE CASCADE,
  redirect_destination INTEGER NULL UNIQUE REFERENCES history_visits(id) ON DELETE CASCADE, origin INTEGER NOT NULL DEFAULT 0,
  generation INTEGER NOT NULL DEFAULT 0, attributes INTEGER NOT NULL DEFAULT 0, score INTEGER NOT NULL DEFAULT 0);
CREATE TABLE metadata (key TEXT NOT NULL UNIQUE, value);
INSERT INTO metadata VALUES ('version', 20);
""")
# Fixed times: 2026-10-01 12:00 UTC is 812_548_800 s after 2001-01-01; one visit 100 days before that.
T = 812_548_800.0
DAY = 86_400.0
items = [
    ("https://www.apple.com/", "apple.com", [(T - 2 * DAY, "Apple", 1), (T - DAY, "Apple", 1)]),
    ("https://swift.org/", "swift.org", [(T - 3 * DAY, "Swift.org", 1)]),
    ("https://news.example.com/a", "news.example.com", [(T, "Article A", 1), (T - 100 * DAY, "Article A (old)", 1)]),
    ("https://broken.example/", "broken.example", [(T - DAY, None, 0)]),
    ("http://127.0.0.1:8780/gamma.html", "127.0.0.1", [(T - 4 * DAY, "Import fixture Gamma", 1)]),
]
for url, domain, visits in items:
    cur = db.execute("INSERT INTO history_items (url, domain_expansion, visit_count, daily_visit_counts, should_recompute_derived_visit_counts, "
                     "visit_count_score) VALUES (?, ?, ?, x'', 0, ?)", (url, domain, len(visits), 100 * len(visits)))
    for time, title, ok in visits:
        db.execute("INSERT INTO history_visits (history_item, visit_time, title, load_successful) VALUES (?, ?, ?, ?)", (cur.lastrowid, time, title, ok))
db.commit()
db.close()
print("safari/Bookmarks.plist safari/History.db")
