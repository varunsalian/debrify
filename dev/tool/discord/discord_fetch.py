#!/usr/bin/env python3
"""
Read recent free-text posts from the Debrify community channels via the bot token,
so nothing posted as plain chat (instead of via /bug or /feature) gets missed.

Read-only. Never posts anything.

Usage:
  python3 discord_fetch.py                       # all watched channels, ~20 msgs each
  python3 discord_fetch.py bug-reports           # a single channel by name
  python3 discord_fetch.py --limit 40            # more per channel
  python3 discord_fetch.py --json                # machine-readable for triage
"""
import argparse
import json
import os
import datetime
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
CFG = json.load(open(os.path.join(HERE, "config.json")))


def load_token():
    if os.environ.get("DISCORD_TOKEN"):
        return os.environ["DISCORD_TOKEN"]
    try:
        for line in open(os.path.join(HERE, ".dev.vars")):
            if line.strip().startswith("DISCORD_TOKEN="):
                return line.split("=", 1)[1].strip()
    except FileNotFoundError:
        pass
    sys.exit("No DISCORD_TOKEN (set env var or dev/tool/discord/.dev.vars)")


TOKEN = load_token()


def api(path):
    req = urllib.request.Request(
        "https://discord.com/api/v10" + path,
        headers={"Authorization": f"Bot {TOKEN}", "User-Agent": "debrify-fetch"},
    )
    with urllib.request.urlopen(req) as r:
        return json.load(r)


def fetch_channel(cid, limit):
    msgs = api(f"/channels/{cid}/messages?limit={limit}")
    msgs.reverse()  # oldest -> newest
    return msgs


def fetch_since(cid, cutoff):
    """Page backwards through history until messages are older than cutoff (a UTC datetime)."""
    out, before = [], None
    while True:
        path = f"/channels/{cid}/messages?limit=100" + (f"&before={before}" if before else "")
        batch = api(path)
        if not batch:
            break
        stop = False
        for m in batch:
            ts = datetime.datetime.fromisoformat(m["timestamp"])
            if ts < cutoff:
                stop = True
                break
            out.append(m)
        before = batch[-1]["id"]
        if stop or len(batch) < 100:
            break
    out.reverse()  # oldest -> newest
    return out


def simplify(m):
    author = m.get("author", {})
    ref = m.get("referenced_message")
    return {
        "id": m["id"],
        "author": author.get("global_name") or author.get("username", "?"),
        "bot": author.get("bot", False),
        "time": m.get("timestamp", "")[:16].replace("T", " "),
        "content": m.get("content", ""),
        "reply_to": (ref or {}).get("author", {}).get("username"),
        "reactions": sum(r.get("count", 0) for r in m.get("reactions", [])),
        "attachments": [a.get("url") for a in m.get("attachments", [])],
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("channel", nargs="?", help="channel name (default: all watched)")
    ap.add_argument("--limit", type=int, default=20, help="messages per channel (when --days not set)")
    ap.add_argument("--days", type=float, help="fetch everything newer than N days ago (paginates)")
    ap.add_argument("--json", action="store_true", help="machine-readable output")
    args = ap.parse_args()

    channels = CFG["channels"]
    if args.channel:
        if args.channel not in channels:
            sys.exit(f"Unknown channel '{args.channel}'. Known: {', '.join(channels)}")
        targets = {args.channel: channels[args.channel]}
    else:
        targets = channels

    cutoff = None
    if args.days:
        cutoff = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=args.days)

    out = {}
    for name, cid in targets.items():
        raw = fetch_since(cid, cutoff) if cutoff else fetch_channel(cid, args.limit)
        out[name] = [simplify(m) for m in raw]

    if args.json:
        print(json.dumps(out, indent=2, ensure_ascii=False))
        return

    for name, msgs in out.items():
        print(f"\n{'=' * 60}\n#{name}  ({len(msgs)} messages)\n{'=' * 60}")
        for m in msgs:
            if not m["content"] and not m["attachments"]:
                continue
            tag = " [BOT]" if m["bot"] else ""
            reply = f"  ↳ replying to {m['reply_to']}" if m["reply_to"] else ""
            react = f"  ({m['reactions']}👍)" if m["reactions"] else ""
            print(f"\n  {m['author']}{tag}  {m['time']}{react}{reply}")
            for line in (m["content"] or "").splitlines():
                print(f"    {line}")
            for a in m["attachments"]:
                print(f"    📎 {a}")


if __name__ == "__main__":
    main()
