#!/usr/bin/env python3
"""YT Daily Digest — YouTube channel triage & summary via Claude CLI.

Fetches today's videos from configured channels, extracts transcripts,
sends to Claude for triage with structured JSON output, and writes results
to SQLite (~/Library/Application Support/Flow/flow.db).
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

import feedparser
from youtube_transcript_api import YouTubeTranscriptApi

YT_RSS_URL = "https://www.youtube.com/feeds/videos.xml?channel_id={}"
MAX_CONTENT_CHARS = 4000
CHANNELS_FILE = Path(__file__).parent / "channels.json"
CHUNK_SIZE = 10
DB_DIR = Path.home() / "Library" / "Application Support" / "Flow"
DB_PATH = DB_DIR / "flow.db"
RETENTION_DAYS = 30

# ── JSON Schema for Claude structured output ─────────────────────────────────

YT_TRIAGE_SCHEMA = json.dumps({
    "type": "object",
    "properties": {
        "items": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "video_id": {"type": "string"},
                    "priority": {"type": "string", "enum": ["high", "medium", "low"]},
                    "title_tr": {"type": "string"},
                    "summary": {"type": "string"},
                    "summary_en": {"type": "string"},
                    "reason": {"type": "string"},
                    "reason_en": {"type": "string"}
                },
                "required": ["video_id", "priority", "title_tr", "summary", "summary_en"]
            }
        }
    },
    "required": ["items"]
})


# ── 0. Channel config ────────────────────────────────────────────────────────

def load_channels() -> List[Dict[str, str]]:
    data = json.loads(CHANNELS_FILE.read_text())
    return data["channels"]


# ── 1. SQLite helpers ────────────────────────────────────────────────────────

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
        except sqlite3.OperationalError:
            pass
    conn.commit()


def insert_item(conn: sqlite3.Connection, item: Dict) -> bool:
    try:
        cursor = conn.execute("""
            INSERT OR IGNORE INTO digest_items
                (source, digest_date, external_id, title, title_tr, url, priority,
                 summary, summary_en, reason, reason_en,
                 channel_name, channel_id, published_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            'yt',
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
            item.get('channel_name'),
            item.get('channel_id'),
            item.get('published_at'),
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


# ── 2. Fetch today's videos from RSS feeds ───────────────────────────────────

def fetch_yt_videos(channels: List[Dict[str, str]], show_all: bool = False) -> List[Dict]:
    today = date.today()

    def _parse_feed(ch):
        try:
            return ch, feedparser.parse(YT_RSS_URL.format(ch["id"]))
        except Exception:
            print(f"  RSS error for {ch['name']}, skipping...", file=sys.stderr)
            return ch, None

    with ThreadPoolExecutor(max_workers=5) as pool:
        results = list(pool.map(_parse_feed, channels))

    videos = []
    for ch, feed in results:
        if feed is None:
            continue

        entries = feed.entries[:3] if show_all else feed.entries
        for entry in entries:
            if not show_all:
                pp = entry.get("published_parsed")
                if pp is None:
                    continue
                pub_date = date(pp.tm_year, pp.tm_mon, pp.tm_mday)
                if pub_date != today:
                    continue

            video_id = entry.get("yt_videoid", "")
            if not video_id:
                link = entry.get("link", "")
                if "v=" in link:
                    video_id = link.split("v=")[-1].split("&")[0]
            if not video_id:
                continue

            link = entry.get("link", "")
            if "/shorts/" in link:
                continue

            videos.append({
                "video_id": video_id,
                "title": entry.get("title", ""),
                "link": link,
                "published": entry.get("published", ""),
                "channel_name": ch["name"],
                "channel_id": ch["id"],
            })

    return videos


# ── 3. Extract transcript via youtube-transcript-api ─────────────────────────

def extract_transcript(video_id: str) -> Optional[str]:
    try:
        ytt_api = YouTubeTranscriptApi()
        fetched = ytt_api.fetch(video_id, languages=["en"])
        text = " ".join(snippet.text for snippet in fetched)
        if len(text) > MAX_CONTENT_CHARS:
            text = text[:MAX_CONTENT_CHARS] + "\n[...truncated]"
        return text
    except Exception:
        return None


# ── 4. Build the Claude prompt ───────────────────────────────────────────────

SYSTEM_PROMPT = """\
Sen bir teknoloji YouTube içerik analistisin. Aşağıda takip edilen YouTube kanallarından bugün yayınlanan videolar ve transkript özetleri var.

Görevin:
1. Her videoyu izlenme önceliğine göre sınıfla: high (İzlenmeli) / medium (Belki) / low (Geç)
2. high ve medium videoların 2-3 cümlelik içerik özetini Türkçe yaz (summary alanı)
3. Aynı özetin İngilizce versiyonunu da yaz (summary_en alanı)
4. Neden izlenmesi gerektiğini Türkçe kısaca açıkla (reason alanı)
5. Aynı açıklamanın İngilizce versiyonunu da yaz (reason_en alanı)
6. Video başlığının doğal ve akıcı Türkçe çevirisini yaz (title_tr alanı)
7. low kategorisindekiler için sadece tek cümle özet yeter (summary, summary_en ve title_tr yeterli)

ÖNEMLI: Türkçe metinlerde ö, ü, ç, ğ, ı, ş gibi Türkçe karakterleri doğru şekilde kullan.

Öncelik kriterleri (kullanıcının ilgi alanlarına göre):
- Yeni çıkan AI teknolojileri, LLM gelişmeleri, model release'leri -> high
- Claude Code, Codex, Gemini CLI ve benzeri AI coding araçları, yeni özellikleri -> high
- Agentic engineering, AI agent framework'leri, tool-use, MCP -> high
- Oyun geliştirme, game engine'ler, oyun teknolojileri -> high
- Pratik ve kullanışlı araçlar, framework'ler, teknik eğitimler -> medium
- Diğer teknik projeler, genel teknoloji haberleri -> medium
- Genel sohbet, vlog, niş konular, tekrar içerikler -> low

Her video için video_id'yi aynen döndür. JSON schema'ya uy.""".strip()


def build_prompts(videos: List[Dict]) -> List[str]:
    video_ids = [v["video_id"] for v in videos]
    with ThreadPoolExecutor(max_workers=5) as pool:
        transcript_map = dict(zip(video_ids, pool.map(extract_transcript, video_ids)))

    chunks = [videos[i:i + CHUNK_SIZE] for i in range(0, len(videos), CHUNK_SIZE)]
    prompts = []

    for chunk in chunks:
        parts = [SYSTEM_PROMPT, "\n---\n"]

        for i, v in enumerate(chunk, 1):
            hdr = (
                f"### Video {i}: {v['title']}\n"
                f"- video_id: {v['video_id']}\n"
                f"- URL: {v['link']}\n"
                f"- Kanal: {v['channel_name']}\n"
                f"- Yayin Tarihi: {v['published']}\n"
            )
            parts.append(hdr)

            transcript = transcript_map.get(v["video_id"])
            if transcript:
                parts.append(f"Transkript:\n{transcript}\n")
            else:
                parts.append("(Transkript alinamadi)\n")

            parts.append("")

        prompts.append("\n".join(parts))

    return prompts


# ── 5. Run Claude CLI for triage (structured output) ────────────────────────

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
         "--json-schema", YT_TRIAGE_SCHEMA,
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


# ── 6. Process Claude response & merge with video metadata ──────────────────

def process_claude_response(triage_results: List[dict], videos: List[Dict]) -> List[Dict]:
    video_map = {v["video_id"]: v for v in videos}
    items = []
    for result in triage_results:
        for tri in result.get("items", []):
            vid = tri.get("video_id", "")
            meta = video_map.get(vid)
            if not meta:
                continue
            items.append({
                "digest_date": str(date.today()),
                "external_id": vid,
                "title": meta["title"],
                "title_tr": tri.get("title_tr"),
                "url": meta["link"],
                "priority": tri["priority"],
                "summary": tri.get("summary"),
                "summary_en": tri.get("summary_en"),
                "reason": tri.get("reason"),
                "reason_en": tri.get("reason_en"),
                "channel_name": meta.get("channel_name"),
                "channel_id": meta.get("channel_id"),
                "published_at": meta.get("published"),
            })
    return items


# ── 7. Main ──────────────────────────────────────────────────────────────────

def main():
    show_all = "--all" in sys.argv

    # DB setup
    conn = get_connection()
    ensure_schema(conn)
    cleanup_old(conn)

    # Record run start
    cursor = conn.execute(
        "INSERT INTO digest_runs (source, status) VALUES ('yt', 'running')"
    )
    run_id = cursor.lastrowid
    conn.commit()

    try:
        print("Loading channels...", file=sys.stderr)
        channels = load_channels()
        print(f"  {len(channels)} channels configured.", file=sys.stderr)

        if show_all:
            print("Fetching last 3 videos per channel...", file=sys.stderr)
        else:
            print("Fetching today's videos via RSS...", file=sys.stderr)
        videos = fetch_yt_videos(channels, show_all=show_all)

        if not videos:
            print("Bugun yeni video yok.", file=sys.stderr)
            conn.execute(
                "UPDATE digest_runs SET status='done', finished_at=datetime('now'), items_added=0 WHERE id=?",
                (run_id,)
            )
            conn.commit()
            return

        # Dedup via DB — skip videos already in DB
        if not show_all:
            existing = set()
            for row in conn.execute(
                "SELECT external_id FROM digest_items WHERE source='yt'"
            ):
                existing.add(row[0])
            selected = [v for v in videos if v["video_id"] not in existing]
            if not selected:
                print("Yeni video yok — tum videolar daha once kaydedildi.", file=sys.stderr)
                conn.execute(
                    "UPDATE digest_runs SET status='done', finished_at=datetime('now'), items_added=0 WHERE id=?",
                    (run_id,)
                )
                conn.commit()
                return
        else:
            selected = videos

        print(f"Got {len(selected)} new videos. Extracting transcripts...", file=sys.stderr)

        prompts = build_prompts(selected)

        print(f"Sending {len(prompts)} chunk(s) to Claude...", file=sys.stderr)
        triage_results = run_parallel_triage(prompts)

        # Merge triage results with video metadata
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
            print(f"{badge} [{item['title']}]({item['url']}) — {item.get('channel_name', '')}")
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
