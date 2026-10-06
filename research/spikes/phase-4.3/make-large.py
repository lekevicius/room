#!/usr/bin/env python3
"""B-84 (Phase 4.3b): generates a large Chrome-shaped profile for the import at
scale, never from a real profile: generated/large/Local State,
generated/large/Default/Bookmarks (5,000 bookmarks in 200 folders: 40 top-level
folders on the bar and in "Other bookmarks", each with four subfolders, 25
links per folder, plus 0 loose links) and generated/large/Default/History
(Chrome's own schema copied from chrome/Default/History; 50,000 URLs and
100,000 visits spread over the last 80 days before the run, so the engine keeps
them all: its limit is 90 days). Deterministic apart from the times. The output
is about 20 MB and is not committed (.gitignore: generated/).
Run from this directory: python3 make-large.py"""
import json, os, random, shutil, sqlite3, time, uuid

OUT = "generated/large"
FOLDERS_TOP = 40
SUBFOLDERS = 4
LINKS_PER_FOLDER = 25
URLS = 50_000
VISITS = 100_000
WEBKIT_OFFSET = 11_644_473_600  # seconds from 1601-01-01 to 1970-01-01

random.seed(43)
now = time.time()


def webkit(seconds):
    return int((seconds + WEBKIT_OFFSET) * 1_000_000)


shutil.rmtree(OUT, ignore_errors=True)
os.makedirs(OUT + "/Default")

next_id = [4]


def node_id():
    next_id[0] += 1
    return str(next_id[0])


def guid(name):
    return str(uuid.uuid5(uuid.NAMESPACE_URL, "room-4.3b/large/" + name))


added = str(webkit(now - 100 * 86_400))
links = folders = 0


def link(name, href):
    global links
    links += 1
    return {"date_added": added, "date_last_used": "0", "guid": guid(href), "id": node_id(), "meta_info": {}, "name": name,
            "type": "url", "url": href}


def folder(name, children):
    global folders
    folders += 1
    return {"children": children, "date_added": added, "date_last_used": "0", "date_modified": added, "guid": guid("f/" + name),
            "id": node_id(), "name": name, "type": "folder"}


def tree(prefix):
    top = []
    for f in range(FOLDERS_TOP // 2):
        name = f"{prefix} {f + 1:02d}"
        subs = [folder(f"{name}.{s + 1}", [link(f"Page {name}.{s + 1}.{n + 1}", f"https://site{f % 97}.example/{prefix.lower()}/{f}/{s}/{n}")
                                           for n in range(LINKS_PER_FOLDER)]) for s in range(SUBFOLDERS)]
        top.append(folder(name, [link(f"Page {name}.{n + 1}", f"https://site{f % 97}.example/{prefix.lower()}/{f}/{n}")
                                 for n in range(LINKS_PER_FOLDER)] + subs))
    return top


bar = tree("Bar")
other = tree("Other")


def root(rid, name, g, children):
    return {"children": children, "date_added": added, "date_last_used": "0", "date_modified": added, "guid": g, "id": rid,
            "name": name, "type": "folder"}


bookmarks = {"checksum": "", "roots": {
    "bookmark_bar": root("1", "Bookmarks bar", "0bc5d13f-2cba-5d74-951f-3f233fe6c908", bar),
    "other": root("2", "Other bookmarks", "82b081ec-3dd3-529c-8475-ab6c344590dd", other),
    "synced": root("3", "Mobile bookmarks", "4cf2e351-0e85-532b-bb37-df045d8f8d0f", [])}, "version": 1}
with open(OUT + "/Default/Bookmarks", "w") as f:
    json.dump(bookmarks, f, indent=1)

with open(OUT + "/Local State", "w") as f:
    json.dump({"profile": {"info_cache": {"Default": {"name": "Large"}}}}, f)

# History in Chrome's own schema.
source = sqlite3.connect("chrome/Default/History")
schema = [sql for (sql,) in source.execute("SELECT sql FROM sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' "
                                           "ORDER BY type DESC")]
meta = source.execute("SELECT key, value FROM meta").fetchall()
source.close()
db = sqlite3.connect(OUT + "/Default/History")
for sql in schema:
    db.execute(sql)
db.executemany("INSERT INTO meta (key, value) VALUES (?, ?)", meta)
span = 80 * 86_400
rows = []
for i in range(URLS):
    rows.append((i + 1, f"https://host{i % 2_000}.example/page/{i}", f"Large history page {i}"))
# Two visits per URL on average: every URL one, half of them two more, typed one in ten.
visits = []
per_url = {}
for i in range(URLS):
    per_url[i + 1] = [now - random.random() * span]
for i in range(VISITS - URLS):
    per_url[random.randint(1, URLS)].append(now - random.random() * span)
visit_id = 0
url_rows = []
for uid, title_url in zip(range(1, URLS + 1), rows):
    times = sorted(per_url[uid])
    typed = 1 if uid % 10 == 0 else 0
    for t in times:
        visit_id += 1
        visits.append((visit_id, uid, webkit(t), 1 if typed else 0x30000000))  # TYPED, or LINK with CHAIN_START|CHAIN_END
    url_rows.append((uid, title_url[1], title_url[2], len(times), len(times) if typed else 0, webkit(times[-1]), 0))
db.executemany("INSERT INTO urls (id, url, title, visit_count, typed_count, last_visit_time, hidden) VALUES (?, ?, ?, ?, ?, ?, ?)", url_rows)
db.executemany("INSERT INTO visits (id, url, visit_time, transition) VALUES (?, ?, ?, ?)", visits)
db.commit()
db.close()
size = sum(os.path.getsize(os.path.join(d, f)) for d, _, fs in os.walk(OUT) for f in fs)
print(f"wrote {OUT}: {links} bookmarks in {folders} folders, {len(url_rows)} URLs, {len(visits)} visits, {size:,} bytes")
