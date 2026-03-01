#!/usr/bin/env python3
"""HN Daily Digest — Hacker News front page triage & summary via Claude CLI.

Fetches top HN stories, extracts article content, sends to Claude for triage
with structured JSON output, and writes results to SQLite
(~/Library/Application Support/Flow/flow.db).
"""

import json
import os
import sqlite3
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional

import requests
import trafilatura

HN_API_URL = "http://hn.algolia.com/api/v1/search"
HN_ITEM_URL = "https://news.ycombinator.com/item?id="
MAX_CONTENT_CHARS = 4000
CHUNK_SIZE = 10
DB_DIR = Path.home() / "Library" / "Application Support" / "Flow"
DB_PATH = DB_DIR / "flow.db"
RETENTION_DAYS = 30

# ── JSON Schema for Claude structured output ─────────────────────────────────

HN_TRIAGE_SCHEMA = json.dumps({
    "type": "object",
    "properties": {
        "items": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "object_id": {"type": "string"},
                    "priority": {"type": "string", "enum": ["high", "medium", "low"]},
                    "title_tr": {"type": "string"},
                    "summary": {"type": "string"},
                    "summary_en": {"type": "string"},
                    "reason": {"type": "string"},
                    "reason_en": {"type": "string"}
                },
                "required": ["object_id", "priority", "title_tr", "summary", "summary_en"]
            }
        }
    },
    "required": ["items"]
})


# ── 0. SQLite helpers ────────────────────────────────────────────────────────

def get_connection() -> sqlite3.Connection:
    DB_DIR.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(DB_PATH))
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA busy_timeout=5000")
    return conn


def ensure_schema(conn: sqlite3.Connection) -> None:
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS digest_items (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            source          TEXT NOT NULL CHECK(source IN ('yt', 'hn')),
            digest_date     TEXT NOT NULL,
            external_id     TEXT NOT NULL,
            title           TEXT NOT NULL,
            url             TEXT NOT NULL,
            priority        TEXT NOT NULL,
            summary         TEXT,
            reason          TEXT,
            channel_name    TEXT,
            channel_id      TEXT,
            published_at    TEXT,
            points          INTEGER,
            num_comments    INTEGER,
            author          TEXT,
            hn_url          TEXT,
            is_read         INTEGER NOT NULL DEFAULT 0,
            is_bookmarked   INTEGER NOT NULL DEFAULT 0,
            created_at      TEXT NOT NULL DEFAULT (datetime('now')),
            UNIQUE(source, external_id)
        );

        CREATE INDEX IF NOT EXISTS idx_items_source_date
            ON digest_items(source, digest_date);
        CREATE INDEX IF NOT EXISTS idx_items_bookmarked
            ON digest_items(is_bookmarked) WHERE is_bookmarked = 1;

        CREATE TABLE IF NOT EXISTS digest_runs (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            source          TEXT NOT NULL CHECK(source IN ('yt', 'hn')),
            started_at      TEXT NOT NULL DEFAULT (datetime('now')),
            finished_at     TEXT,
            status          TEXT NOT NULL DEFAULT 'running',
            items_added     INTEGER DEFAULT 0,
            error_message   TEXT
        );
    """)
    for col, col_type in [("title_tr", "TEXT"), ("summary_en", "TEXT"), ("reason_en", "TEXT")]:
        try:
            conn.execute(f"ALTER TABLE digest_items ADD COLUMN {col} {col_type}")
            conn.commit()
        except sqlite3.OperationalError:
            pass


def insert_item(conn: sqlite3.Connection, item: Dict) -> bool:
    try:
        cursor = conn.execute("""
            INSERT OR IGNORE INTO digest_items
                (source, digest_date, external_id, title, title_tr, url, priority,
                 summary, summary_en, reason, reason_en,
                 points, num_comments, author, hn_url)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            'hn',
            item['digest_date'],
            item['external_id'],
            item['title'],
            item.get('title_tr'),
            item['url'],
            item['priority'],
            item.get('summary'),
            item.get('summary_en'),
            item.get('reason'),
            item.get('reason_en'),
            item.get('points'),
            item.get('num_comments'),
            item.get('author'),
            item.get('hn_url'),
        ))
        return cursor.rowcount > 0
    except sqlite3.Error as e:
        print(f"  DB insert error: {e}", file=sys.stderr)
        return False


def cleanup_old(conn: sqlite3.Connection) -> None:
    cutoff = (date.today() - timedelta(days=RETENTION_DAYS)).isoformat()
    conn.execute(
        "DELETE FROM digest_items WHERE digest_date < ? AND is_bookmarked = 0",
        (cutoff,)
    )
    conn.execute(
        "DELETE FROM digest_runs WHERE started_at < ?",
        (cutoff,)
    )
    conn.commit()


# ── 1. Fetch top stories from Algolia HN API ─────────────────────────────────

def fetch_hn_stories() -> List[Dict]:
    # 1) Front page snapshot
    front_resp = requests.get(
        HN_API_URL,
        params={"tags": "front_page", "hitsPerPage": 30},
        timeout=15,
    )
    front_resp.raise_for_status()
    front_hits = front_resp.json().get("hits", [])

    # 2) Today's stories (all points, sorted by relevance)
    start_of_today = int(datetime.combine(date.today(), datetime.min.time()).timestamp())
    today_resp = requests.get(
        HN_API_URL,
        params={
            "tags": "story",
            "numericFilters": "created_at_i>{}".format(start_of_today),
            "hitsPerPage": 30,
        },
        timeout=15,
    )
    today_resp.raise_for_status()
    today_hits = today_resp.json().get("hits", [])

    # Merge & dedup by objectID
    merged = {}
    for h in front_hits + today_hits:
        oid = h.get("objectID", "")
        if oid not in merged:
            merged[oid] = h

    # Sort by points descending
    sorted_hits = sorted(merged.values(), key=lambda h: h.get("points", 0), reverse=True)

    stories = []
    for h in sorted_hits:
        stories.append({
            "title": h.get("title", ""),
            "url": h.get("url"),
            "points": h.get("points", 0),
            "num_comments": h.get("num_comments", 0),
            "author": h.get("author", ""),
            "object_id": h.get("objectID", ""),
            "story_text": h.get("story_text"),
        })
    return stories


# ── 2. Extract article content with trafilatura ──────────────────────────────

def extract_article(url: str) -> Optional[str]:
    try:
        downloaded = trafilatura.fetch_url(url)
        if downloaded is None:
            return None
        text = trafilatura.extract(downloaded)
        if text and len(text) > MAX_CONTENT_CHARS:
            text = text[:MAX_CONTENT_CHARS] + "\n[...truncated]"
        return text
    except Exception:
        return None


# ── 3. Build the Claude prompt ────────────────────────────────────────────────

SYSTEM_PROMPT = """\
Sen bir teknoloji haber analistisin. Aşağıda Hacker News front page'inden hikayeler ve makale içerikleri var.

Görevin:
1. Her hikayeyi önem derecesine göre sınıfla: high (Yüksek) / medium (Orta) / low (Düşük)
2. high ve medium önemdeki hikayelerin 2-3 cümlelik özetini Türkçe yaz (summary alanı)
3. Aynı özetin İngilizce versiyonunu da yaz (summary_en alanı)
4. Neden önemli olduğunu Türkçe kısaca açıkla (reason alanı)
5. Aynı açıklamanın İngilizce versiyonunu da yaz (reason_en alanı)
6. Hikaye başlığının doğal ve akıcı Türkçe çevirisini yaz (title_tr alanı)
7. low önemdekiler için sadece tek cümle özet yeter (summary, summary_en ve title_tr yeterli)

ÖNEMLI: Türkçe metinlerde ö, ü, ç, ğ, ı, ş gibi Türkçe karakterleri doğru şekilde kullan.

Önem kriterleri (kullanıcının ilgi alanlarına göre):
- Yeni çıkan AI teknolojileri, LLM gelişmeleri, model release'leri -> high
- Claude Code, Codex, Gemini CLI ve benzeri AI coding araçları, yeni özellikleri -> high
- Agentic engineering, AI agent framework'leri, tool-use, MCP -> high
- Oyun geliştirme, game engine'ler, oyun teknolojileri -> high
- Pratik ve kullanışlı GitHub repoları, geliştirici araçları -> medium
- Diğer teknik projeler, kütüphaneler, ilginç hack'ler -> medium
- Genel haberler, politika, kişisel blog yazıları, niş konular -> low

Her hikaye için object_id'yi aynen döndür. JSON schema'ya uy.""".strip()


def build_prompts(stories: List[Dict]) -> List[str]:
    # Extract articles in parallel
    urls = [s["url"] for s in stories if s["url"]]
    with ThreadPoolExecutor(max_workers=5) as pool:
        content_map = dict(zip(urls, pool.map(extract_article, urls)))

    chunks = [stories[i:i + CHUNK_SIZE] for i in range(0, len(stories), CHUNK_SIZE)]
    prompts = []

    for chunk in chunks:
        parts = [SYSTEM_PROMPT, "\n---\n"]

        for i, s in enumerate(chunk, 1):
            hn_link = f"{HN_ITEM_URL}{s['object_id']}"
            hdr = (
                f"### Hikaye {i}: {s['title']}\n"
                f"- object_id: {s['object_id']}\n"
                f"- URL: {s['url'] or hn_link}\n"
                f"- HN: {hn_link}\n"
                f"- Puan: {s['points']} | Yorum: {s['num_comments']} | Yazar: {s['author']}\n"
            )
            parts.append(hdr)

            if s["url"]:
                content = content_map.get(s["url"])
                if content:
                    parts.append(f"Makale icerigi:\n{content}\n")
                else:
                    parts.append("(Makale icerigi alinamadi)\n")
            elif s["story_text"]:
                parts.append(f"Metin:\n{s['story_text']}\n")
            else:
                parts.append("(Icerik yok)\n")

            parts.append("")

        prompts.append("\n".join(parts))

    return prompts


# ── 4. Run Claude CLI for triage (structured output) ─────────────────────────

_CLAUDE_ENV = {k: v for k, v in os.environ.items() if k != "CLAUDECODE"}
_CLAUDE_ENV["PATH"] = (
    os.path.expanduser("~/.local/bin")
    + os.pathsep
    + _CLAUDE_ENV.get("PATH", "/usr/bin:/bin")
)


def run_claude_triage(prompt: str) -> dict:
    result = subprocess.run(
        ["claude", "-p",
         "--model", "sonnet",
         "--output-format", "json",
         "--json-schema", HN_TRIAGE_SCHEMA,
         "--no-session-persistence"],
        input=prompt,
        capture_output=True,
        text=True,
        timeout=300,
        env=_CLAUDE_ENV,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"Claude CLI error (rc={result.returncode}):\n{result.stderr}"
        )
    response = json.loads(result.stdout)
    return response["structured_output"]


def run_parallel_triage(prompts: List[str]) -> List[dict]:
    with ThreadPoolExecutor(max_workers=len(prompts)) as pool:
        return list(pool.map(run_claude_triage, prompts))


# ── 5. Process Claude response & merge with story metadata ──────────────────

def process_claude_response(triage_results: List[dict], stories: List[Dict]) -> List[Dict]:
    story_map = {s["object_id"]: s for s in stories}
    items = []
    for result in triage_results:
        for tri in result.get("items", []):
            oid = tri.get("object_id", "")
            meta = story_map.get(oid)
            if not meta:
                continue
            hn_link = f"{HN_ITEM_URL}{oid}"
            items.append({
                "digest_date": str(date.today()),
                "external_id": oid,
                "title": meta["title"],
                "title_tr": tri.get("title_tr"),
                "url": meta.get("url") or hn_link,
                "priority": tri["priority"],
                "summary": tri.get("summary"),
                "summary_en": tri.get("summary_en"),
                "reason": tri.get("reason"),
                "reason_en": tri.get("reason_en"),
                "points": meta.get("points"),
                "num_comments": meta.get("num_comments"),
                "author": meta.get("author"),
                "hn_url": hn_link,
            })
    return items


# ── 6. Main ──────────────────────────────────────────────────────────────────

def main():
    show_all = "--all" in sys.argv

    # DB setup
    conn = get_connection()
    ensure_schema(conn)
    cleanup_old(conn)

    # Record run start
    cursor = conn.execute(
        "INSERT INTO digest_runs (source, status) VALUES ('hn', 'running')"
    )
    run_id = cursor.lastrowid
    conn.commit()

    try:
        print("Fetching HN stories (front page + today)...", file=sys.stderr)
        stories = fetch_hn_stories()

        # Dedup via DB — skip stories already in DB
        if not show_all:
            existing = set()
            for row in conn.execute(
                "SELECT external_id FROM digest_items WHERE source='hn'"
            ):
                existing.add(row[0])
            selected = [s for s in stories if s["object_id"] not in existing]
            if not selected:
                print("Yeni hikaye yok — tum hikayeler daha once kaydedildi.", file=sys.stderr)
                conn.execute(
                    "UPDATE digest_runs SET status='done', finished_at=datetime('now'), items_added=0 WHERE id=?",
                    (run_id,)
                )
                conn.commit()
                return
        else:
            selected = stories

        print(f"Got {len(selected)} stories. Extracting articles...", file=sys.stderr)

        prompts = build_prompts(selected)

        print(f"Sending {len(prompts)} chunk(s) to Claude...", file=sys.stderr)
        triage_results = run_parallel_triage(prompts)

        # Merge triage results with story metadata
        items = process_claude_response(triage_results, selected)

        # Write to DB
        added = 0
        for item in items:
            if insert_item(conn, item):
                added += 1
        conn.commit()

        print(f"Done! {added} items written to DB.", file=sys.stderr)

        # Also print markdown summary to stdout for backwards compat
        for item in items:
            badge = {"high": "🔴", "medium": "🟡", "low": "🟢"}.get(item["priority"], "⚪")
            pts = item.get("points", 0)
            comments = item.get("num_comments", 0)
            print(f"{badge} [{item['title']}]({item['url']}) ({pts} pts, {comments} comments)")
            if item.get("summary"):
                print(f"   {item['summary']}")
            print()

        conn.execute(
            "UPDATE digest_runs SET status='done', finished_at=datetime('now'), items_added=? WHERE id=?",
            (added, run_id)
        )
        conn.commit()

    except Exception as e:
        conn.execute(
            "UPDATE digest_runs SET status='error', finished_at=datetime('now'), error_message=? WHERE id=?",
            (str(e), run_id)
        )
        conn.commit()
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    main()
