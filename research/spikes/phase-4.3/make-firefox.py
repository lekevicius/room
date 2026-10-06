#!/usr/bin/env python3
"""Writes the Firefox fixture (Phase 4.3b) from the schema Chromium's
chrome/utility/importer/firefox_importer.cc reads, never from a real profile:
firefox/places.sqlite with moz_places (id, url, title, visit_count, hidden,
typed, last_visit_date), moz_historyvisits (id, from_visit, place_id,
visit_date, visit_type) and moz_bookmarks (id, type 1 = url, 2 = folder,
3 = separator; fk -> moz_places.id, parent, position, title, dateAdded,
guid). Times are microseconds since 1970, fixed around 2026-10-01.
Run from this directory."""
import os, sqlite3

BASE = 1_790_856_000 * 1_000_000  # 2026-10-01T12:00:00Z in microseconds
HOUR = 3_600 * 1_000_000
DAY = 24 * HOUR

path = "firefox/places.sqlite"
os.makedirs("firefox", exist_ok=True)
if os.path.exists(path):
    os.remove(path)
db = sqlite3.connect(path)
db.executescript("""
CREATE TABLE moz_places (id INTEGER PRIMARY KEY, url LONGVARCHAR, title LONGVARCHAR, rev_host LONGVARCHAR,
  visit_count INTEGER DEFAULT 0, hidden INTEGER DEFAULT 0 NOT NULL, typed INTEGER DEFAULT 0 NOT NULL,
  frecency INTEGER DEFAULT -1 NOT NULL, last_visit_date INTEGER, guid TEXT, foreign_count INTEGER DEFAULT 0 NOT NULL,
  url_hash INTEGER DEFAULT 0 NOT NULL, description TEXT, preview_image_url TEXT, origin_id INTEGER);
CREATE TABLE moz_historyvisits (id INTEGER PRIMARY KEY, from_visit INTEGER, place_id INTEGER, visit_date INTEGER,
  visit_type INTEGER, session INTEGER, source INTEGER DEFAULT 0 NOT NULL, triggeringPlaceId INTEGER);
CREATE TABLE moz_bookmarks (id INTEGER PRIMARY KEY, type INTEGER, fk INTEGER DEFAULT NULL, parent INTEGER,
  position INTEGER, title LONGVARCHAR, keyword_id INTEGER, folder_type TEXT, dateAdded INTEGER, lastModified INTEGER,
  guid TEXT, syncStatus INTEGER NOT NULL DEFAULT 0, syncChangeCounter INTEGER NOT NULL DEFAULT 1);
CREATE TABLE moz_keywords (id INTEGER PRIMARY KEY AUTOINCREMENT, keyword TEXT UNIQUE, place_id INTEGER, post_data TEXT);
""")

places = {}


def place(url, title, hidden=0, typed=0):
    pid = len(places) + 1
    places[url] = pid
    db.execute("INSERT INTO moz_places (id, url, title, hidden, typed, guid) VALUES (?, ?, ?, ?, ?, ?)",
               (pid, url, title, hidden, typed, "place%07d" % pid))
    return pid


visit_id = [0]


def visit(pid, when, kind):
    visit_id[0] += 1
    db.execute("INSERT INTO moz_historyvisits (id, from_visit, place_id, visit_date, visit_type) VALUES (?, 0, ?, ?, ?)",
               (visit_id[0], pid, when, kind))


# History: link (1), typed (2), bookmark (3) visits count; embed (4), redirects (5, 6), download (7),
# framed link (8) and reload (9) do not.
mozilla = place("https://www.mozilla.org/en-US/firefox/", "Firefox Browser", typed=1)
visit(mozilla, BASE - 2 * DAY, 2)
visit(mozilla, BASE - DAY, 2)
visit(mozilla, BASE - HOUR, 1)
mdn = place("https://developer.mozilla.org/en-US/docs/Web", "Web technology for developers")
visit(mdn, BASE - 3 * DAY, 1)
visit(mdn, BASE - 3 * DAY + 1_000_000, 9)  # a reload: not a visit
rust = place("https://www.rust-lang.org/", "Rust Programming Language")
visit(rust, BASE - 5 * DAY, 3)
redirect = place("http://mozilla.org/", "", hidden=1)  # a redirect source Firefox hides
visit(redirect, BASE - DAY - 1_000_000, 5)
visit(redirect, BASE - DAY - 2_000_000, 1)
embed = place("https://ads.example/frame.html", "Frame")  # only an embedded frame's visit
visit(embed, BASE - DAY, 4)
recipes = place("https://cooking.example/soup", "Soup")
visit(recipes, BASE - 120 * DAY, 1)  # older than the engine keeps (counted as expired by the engine)
visit(recipes, BASE - 10 * DAY, 1)
# Bookmarked pages never visited (visit_count 0): no history line.
for url, title in [("https://kernel.org/", "The Linux Kernel Archives"), ("https://www.python.org/", "Python"),
                   ("https://news.example/", "News"), ("https://maps.example/", "Maps"),
                   ("https://phone.example/app", "On the phone"), ("place:sort=8&maxResults=10", "Recent Tags")]:
    place(url, title)
for url, pid in places.items():
    count = db.execute("SELECT count(*) FROM moz_historyvisits WHERE place_id = ?", (pid,)).fetchone()[0]
    last = db.execute("SELECT max(visit_date) FROM moz_historyvisits WHERE place_id = ?", (pid,)).fetchone()[0]
    db.execute("UPDATE moz_places SET visit_count = ?, last_visit_date = ? WHERE id = ?", (count, last, pid))

bookmark_id = [0]


def bookmark(kind, parent, position, title, fk=None, guid=None, when=BASE - 30 * DAY):
    bookmark_id[0] += 1
    bid = bookmark_id[0]
    db.execute("INSERT INTO moz_bookmarks (id, type, fk, parent, position, title, dateAdded, lastModified, guid) "
               "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
               (bid, kind, fk, parent, position, title, when, when, guid or "bookmark%04d" % bid))
    return bid


root = bookmark(2, 0, 0, "", guid="root________")
menu = bookmark(2, root, 0, "menu", guid="menu________")
toolbar = bookmark(2, root, 1, "toolbar", guid="toolbar_____")
bookmark(2, root, 2, "tags", guid="tags________")
unfiled = bookmark(2, root, 3, "unfiled", guid="unfiled_____")
mobile = bookmark(2, root, 4, "mobile", guid="mobile______")

# The toolbar: two links, a separator, a folder with a subfolder, a link titled by its page (empty title).
bookmark(1, toolbar, 0, "Firefox", fk=mozilla)
bookmark(1, toolbar, 1, "MDN", fk=mdn)
bookmark(3, toolbar, 2, None)
dev = bookmark(2, toolbar, 3, "Dev")
bookmark(1, dev, 0, "Rust", fk=rust)
deeper = bookmark(2, dev, 1, "Kernel")
bookmark(1, deeper, 0, "kernel.org", fk=places["https://kernel.org/"])
bookmark(1, toolbar, 4, "", fk=places["https://www.python.org/"])
# The menu: a folder, a smart bookmark (place:, skipped by the plan), a link whose page row is missing.
food = bookmark(2, menu, 0, "Recipes")
bookmark(1, food, 0, "Soup", fk=recipes)
bookmark(1, menu, 1, "Recent Tags", fk=places["place:sort=8&maxResults=10"])
bookmark(1, menu, 2, "Lost page", fk=999)
# Other Bookmarks and mobile.
bookmark(1, unfiled, 0, "News", fk=places["https://news.example/"])
bookmark(1, unfiled, 1, "Maps", fk=places["https://maps.example/"])
bookmark(1, mobile, 0, "On the phone", fk=places["https://phone.example/app"])

db.commit()
db.execute("VACUUM")
db.close()
print("wrote", path, os.path.getsize(path), "bytes:", len(places), "places,", visit_id[0], "visits,", bookmark_id[0], "bookmark rows")
