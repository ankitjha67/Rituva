"""Resolve real YouTube video IDs for Rituva's dishes — the only sanctioned way a
`watch?v=` link ever enters the app.

Without this cache the app links to YouTube *search* endpoints, which always resolve.
Run this and those upgrade to direct links to a specific chef's video on the dish.

    export YOUTUBE_API_KEY=...          # https://console.cloud.google.com → YouTube Data API v3
    python scripts/resolve_youtube.py --limit 200

Cost: the Data API charges 100 quota units per search; the free tier is 10,000/day, so
~100 lookups/day. The script caches every hit to `rituva/youtube_cache.json` and skips
anything already resolved, so re-running continues where it left off.

Nothing here guesses: a video ID is written only if the API returned it, and only if the
result really is from that chef's channel.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from rituva.cooking import CHEFS, _dish_query, _rank_chefs  # noqa: E402
from rituva.knowledge import RECIPES  # noqa: E402

API = "https://www.googleapis.com/youtube/v3/search"
CACHE_PATH = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                          "rituva", "youtube_cache.json")


def load_cache() -> dict:
    if os.path.exists(CACHE_PATH):
        with open(CACHE_PATH, "r", encoding="utf-8") as fh:
            return json.load(fh)
    return {}


def save_cache(cache: dict) -> None:
    with open(CACHE_PATH, "w", encoding="utf-8") as fh:
        json.dump(cache, fh, indent=1, ensure_ascii=False, sort_keys=True)


def channel_id_for(handle: str, key: str) -> str | None:
    """Resolve @handle -> channelId (1 unit via the channels endpoint)."""
    url = ("https://www.googleapis.com/youtube/v3/channels?part=id&forHandle="
           f"{urllib.parse.quote(handle)}&key={key}")
    try:
        with urllib.request.urlopen(url, timeout=15) as r:
            data = json.loads(r.read().decode())
        items = data.get("items") or []
        return items[0]["id"] if items else None
    except Exception as e:
        print(f"  ! channel lookup failed for @{handle}: {e}")
        return None


def search_video(query: str, channel_id: str, key: str) -> dict | None:
    """Top video for `query` within one channel. Returns None rather than a guess."""
    params = urllib.parse.urlencode({
        "part": "snippet", "q": query, "channelId": channel_id, "type": "video",
        "maxResults": 1, "order": "relevance", "key": key,
    })
    try:
        with urllib.request.urlopen(f"{API}?{params}", timeout=15) as r:
            data = json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        body = e.read().decode()[:200]
        print(f"  ! HTTP {e.code}: {body}")
        if e.code == 403:
            raise SystemExit("Quota exhausted or key rejected — stopping so nothing is faked.")
        return None
    except Exception as e:
        print(f"  ! {e}")
        return None
    items = data.get("items") or []
    if not items:
        return None
    it = items[0]
    # Only accept a result that genuinely lives on the channel we asked for.
    if it["snippet"].get("channelId") != channel_id:
        return None
    return {"video_id": it["id"]["videoId"], "title": it["snippet"]["title"],
            "channel": it["snippet"].get("channelTitle", "")}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=80, help="how many recipes to resolve this run")
    ap.add_argument("--chefs", type=int, default=2, help="how many chefs per recipe")
    ap.add_argument("--only", default="", help="comma-separated recipe ids (optional)")
    args = ap.parse_args()

    key = os.environ.get("YOUTUBE_API_KEY", "").strip()
    if not key:
        raise SystemExit("Set YOUTUBE_API_KEY first. Without it the app still works — it uses "
                         "YouTube search links, which never break.")

    cache = load_cache()
    print(f"cache: {len(cache)} recipes already resolved")

    # Resolve each chef's channelId once (cheap: 1 unit each).
    channels: dict = {}
    for c in CHEFS:
        cid = channel_id_for(c["handle"], key)
        if cid:
            channels[c["id"]] = cid
        print(f"  @{c['handle']:24} -> {cid or 'NOT FOUND'}")
    if not channels:
        raise SystemExit("No channels resolved — check the API key.")

    todo = [r for r in RECIPES.values() if r.id not in cache]
    if args.only:
        want = {s.strip() for s in args.only.split(",")}
        todo = [r for r in RECIPES.values() if r.id in want]
    todo = todo[:args.limit]
    print(f"\nresolving {len(todo)} recipes x {args.chefs} chefs "
          f"(~{len(todo) * args.chefs * 100} quota units)\n")

    for i, recipe in enumerate(todo, 1):
        q = _dish_query(recipe)
        hits = []
        for chef in _rank_chefs(recipe)[:args.chefs]:
            cid = channels.get(chef["id"])
            if not cid:
                continue
            found = search_video(q, cid, key)
            if found:
                hits.append({"chef_id": chef["id"], **found})
            time.sleep(0.1)                      # be polite to the API
        if hits:
            cache[recipe.id] = hits
            save_cache(cache)                    # save as we go — a crash loses nothing
        print(f"[{i}/{len(todo)}] {recipe.name}: {len(hits)} video(s)")

    print(f"\ndone — {len(cache)} recipes cached at {CACHE_PATH}")
    print("Restart the API server to serve direct video links.")


if __name__ == "__main__":
    main()
