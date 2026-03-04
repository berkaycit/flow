#!/usr/bin/env python3
"""Reddit Daily Digest — subreddit top posts triage & summary via Claude CLI.

Fetches top Reddit posts from configured subreddits, sends to Claude for triage
with structured JSON output, and writes results to SQLite
(~/Library/Application Support/Flow/flow.db).
"""

import json
import os
import sqlite3
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from datetime import date, timedelta
from pathlib import Path
from typing import Dict, List

import requests

REDDIT_BASE_URL = "https://www.reddit.com/r/{}/top.json?t=day&limit=25"
USER_AGENT = "Flow-Digest/1.0"
MAX_CONTENT_CHARS = 4000
CHUNK_SIZE = 10
DB_DIR = Path.home() / "Library" / "Application Support" / "Flow"
DB_PATH = DB_DIR / "flow.db"
RETENTION_DAYS = 30

# ── JSON Schema for Claude structured output ─────────────────────────────────

REDDIT_TRIAGE_SCHEMA = json.dumps({
    "type": "object",
    "properties": {
        "items": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "post_id": {"type": "string"},
                    "priority": {"type": "string", "enum": ["high", "medium", "low"]},
                    "title_tr": {"type": "string"},
                    "summary": {"type": "string"},
                    "summary_en": {"type": "string"},
                    "reason": {"type": "string"},
                    "reason_en": {"type": "string"}
                },
                "required": ["post_id", "priority", "title_tr", "summary", "summary_en"]
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
            source          TEXT NOT NULL CHECK(source IN ('yt', 'hn', 'reddit')),
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
            source          TEXT NOT NULL CHECK(source IN ('yt', 'hn', 'reddit')),
            started_at      TEXT NOT NULL DEFAULT (datetime('now')),
            finished_at     TEXT,
            status          TEXT NOT NULL DEFAULT 'running',
            items_added     INTEGER DEFAULT 0,
            error_message   TEXT
        );
    """)
    for col, col_type in [("title_tr", "TEXT"), ("summary_en", "TEXT"), ("reason_en", "TEXT"), ("notebook_url", "TEXT")]:
        try:
            conn.execute(f"ALTER TABLE digest_items ADD COLUMN {col} {col_type}")
        except sqlite3.OperationalError:
            pass
    _migrate_check_constraints(conn)
    conn.commit()


def _migrate_check_constraints(conn: sqlite3.Connection) -> None:
    """Migrate CHECK constraints to include 'reddit' if needed."""
    cursor = conn.execute(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name='digest_items'"
    )
    row = cursor.fetchone()
    if not row or "'reddit'" in row[0]:
        return

    conn.executescript("""
        ALTER TABLE digest_items RENAME TO _digest_items_old;

        CREATE TABLE digest_items (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            source          TEXT NOT NULL CHECK(source IN ('yt', 'hn', 'reddit')),
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
            title_tr        TEXT,
            summary_en      TEXT,
            reason_en       TEXT,
            notebook_url    TEXT,
            UNIQUE(source, external_id)
        );

        INSERT INTO digest_items SELECT
            id, source, digest_date, external_id, title, url, priority,
            summary, reason, channel_name, channel_id, published_at,
            points, num_comments, author, hn_url, is_read, is_bookmarked,
            created_at, title_tr, summary_en, reason_en, notebook_url
        FROM _digest_items_old;

        DROP TABLE _digest_items_old;

        CREATE INDEX IF NOT EXISTS idx_items_source_date
            ON digest_items(source, digest_date);
        CREATE INDEX IF NOT EXISTS idx_items_bookmarked
            ON digest_items(is_bookmarked) WHERE is_bookmarked = 1;
    """)

    # Also migrate digest_runs
    cursor2 = conn.execute(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name='digest_runs'"
    )
    row2 = cursor2.fetchone()
    if row2 and "'reddit'" not in row2[0]:
        conn.executescript("""
            ALTER TABLE digest_runs RENAME TO _digest_runs_old;

            CREATE TABLE digest_runs (
                id              INTEGER PRIMARY KEY AUTOINCREMENT,
                source          TEXT NOT NULL CHECK(source IN ('yt', 'hn', 'reddit')),
                started_at      TEXT NOT NULL DEFAULT (datetime('now')),
                finished_at     TEXT,
                status          TEXT NOT NULL DEFAULT 'running',
                items_added     INTEGER DEFAULT 0,
                error_message   TEXT
            );

            INSERT INTO digest_runs SELECT * FROM _digest_runs_old;
            DROP TABLE _digest_runs_old;
        """)


def insert_item(conn: sqlite3.Connection, item: Dict) -> bool:
    try:
        cursor = conn.execute("""
            INSERT OR IGNORE INTO digest_items
                (source, digest_date, external_id, title, title_tr, url, priority,
                 summary, summary_en, reason, reason_en,
                 points, num_comments, author, channel_name, hn_url)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            'reddit',
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
            item.get('subreddit'),
            item.get('reddit_url'),
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


# ── 1. Load config ───────────────────────────────────────────────────────────

def load_subreddits() -> List[str]:
    config_path = Path(__file__).parent / "subreddits.json"
    with open(config_path) as f:
        return json.load(f)["subreddits"]


# ── 2. Fetch top posts from Reddit JSON API ──────────────────────────────────

def fetch_subreddit(sub: str) -> List[Dict]:
    url = REDDIT_BASE_URL.format(sub)
    resp = requests.get(url, headers={"User-Agent": USER_AGENT}, timeout=15)
    resp.raise_for_status()
    data = resp.json().get("data", {}).get("children", [])
    posts = []
    for child in data:
        p = child.get("data", {})
        post_id = p.get("id", "")
        posts.append({
            "title": p.get("title", ""),
            "url": p.get("url", ""),
            "points": p.get("score", 0),
            "num_comments": p.get("num_comments", 0),
            "author": p.get("author", ""),
            "post_id": post_id,
            "subreddit": p.get("subreddit", sub),
            "selftext": p.get("selftext", ""),
            "permalink": p.get("permalink", ""),
            "is_self": p.get("is_self", False),
        })
    return posts


def fetch_all_subreddits(subreddits: List[str]) -> List[Dict]:
    all_posts = []
    with ThreadPoolExecutor(max_workers=len(subreddits)) as pool:
        results = pool.map(fetch_subreddit, subreddits)
        for posts in results:
            all_posts.extend(posts)

    # Dedup by post_id, sort by score descending
    seen = {}
    for p in all_posts:
        pid = p["post_id"]
        if pid not in seen:
            seen[pid] = p
    return sorted(seen.values(), key=lambda p: p.get("points", 0), reverse=True)


# ── 3. Build the Claude prompt ────────────────────────────────────────────────

SYSTEM_PROMPT = """\
Sen bir teknoloji haber analistisin. Aşağıda Reddit'ten gelen postlar var.

Görevin:
1. Her postu önem derecesine göre sınıfla: high (Yüksek) / medium (Orta) / low (Düşük)
2. high ve medium önemdeki postların 2-3 cümlelik özetini Türkçe yaz (summary alanı)
3. Aynı özetin İngilizce versiyonunu da yaz (summary_en alanı)
4. Neden önemli olduğunu Türkçe kısaca açıkla (reason alanı)
5. Aynı açıklamanın İngilizce versiyonunu da yaz (reason_en alanı)
6. Post başlığının doğal ve akıcı Türkçe çevirisini yaz (title_tr alanı)
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

Her post için post_id'yi aynen döndür. JSON schema'ya uy.""".strip()


def build_prompts(posts: List[Dict]) -> List[str]:
    chunks = [posts[i:i + CHUNK_SIZE] for i in range(0, len(posts), CHUNK_SIZE)]
    prompts = []

    for chunk in chunks:
        parts = [SYSTEM_PROMPT, "\n---\n"]

        for i, p in enumerate(chunk, 1):
            permalink = f"https://www.reddit.com{p['permalink']}" if p['permalink'] else ""
            hdr = (
                f"### Post {i}: {p['title']}\n"
                f"- post_id: {p['post_id']}\n"
                f"- Subreddit: r/{p['subreddit']}\n"
                f"- URL: {p['url']}\n"
                f"- Reddit: {permalink}\n"
                f"- Puan: {p['points']} | Yorum: {p['num_comments']} | Yazar: u/{p['author']}\n"
            )
            parts.append(hdr)

            if p["selftext"]:
                text = p["selftext"]
                if len(text) > MAX_CONTENT_CHARS:
                    text = text[:MAX_CONTENT_CHARS] + "\n[...truncated]"
                parts.append(f"Post icerigi:\n{text}\n")
            else:
                parts.append("(Link post — icerik yok)\n")

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
         "--model", "haiku",
         "--output-format", "json",
         "--json-schema", REDDIT_TRIAGE_SCHEMA,
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


# ── 5. Process Claude response & merge with post metadata ───────────────────

def process_claude_response(triage_results: List[dict], posts: List[Dict]) -> List[Dict]:
    post_map = {p["post_id"]: p for p in posts}
    items = []
    for result in triage_results:
        for tri in result.get("items", []):
            pid = tri.get("post_id", "")
            meta = post_map.get(pid)
            if not meta:
                continue
            permalink = f"https://www.reddit.com{meta['permalink']}" if meta['permalink'] else meta['url']
            items.append({
                "digest_date": str(date.today()),
                "external_id": pid,
                "title": meta["title"],
                "title_tr": tri.get("title_tr"),
                "url": meta.get("url") or permalink,
                "priority": tri["priority"],
                "summary": tri.get("summary"),
                "summary_en": tri.get("summary_en"),
                "reason": tri.get("reason"),
                "reason_en": tri.get("reason_en"),
                "points": meta.get("points"),
                "num_comments": meta.get("num_comments"),
                "author": meta.get("author"),
                "subreddit": meta.get("subreddit"),
                "reddit_url": permalink,
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
        "INSERT INTO digest_runs (source, status) VALUES ('reddit', 'running')"
    )
    run_id = cursor.lastrowid
    conn.commit()

    try:
        subreddits = load_subreddits()
        print(f"Fetching Reddit posts from {len(subreddits)} subreddits...", file=sys.stderr)
        posts = fetch_all_subreddits(subreddits)

        # Dedup via DB — skip posts already in DB
        if not show_all:
            post_ids = [p["post_id"] for p in posts]
            placeholders = ",".join("?" * len(post_ids))
            existing = set(
                row[0] for row in conn.execute(
                    f"SELECT external_id FROM digest_items WHERE source='reddit' AND external_id IN ({placeholders})",
                    post_ids,
                )
            )
            selected = [p for p in posts if p["post_id"] not in existing]
            if not selected:
                print("Yeni post yok — tum postlar daha once kaydedildi.", file=sys.stderr)
                conn.execute(
                    "UPDATE digest_runs SET status='done', finished_at=datetime('now'), items_added=0 WHERE id=?",
                    (run_id,)
                )
                conn.commit()
                return
        else:
            selected = posts

        print(f"Got {len(selected)} posts. Sending to Claude...", file=sys.stderr)

        prompts = build_prompts(selected)

        print(f"Sending {len(prompts)} chunk(s) to Claude...", file=sys.stderr)
        triage_results = run_parallel_triage(prompts)

        # Merge triage results with post metadata
        items = process_claude_response(triage_results, selected)

        # Write to DB
        added = 0
        for item in items:
            if insert_item(conn, item):
                added += 1
        conn.commit()

        print(f"Done! {added} items written to DB.", file=sys.stderr)

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
