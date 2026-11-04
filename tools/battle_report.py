"""Summarises the cloud battle log (server/battle_logs.sql) for balancing.

    python tools/battle_report.py [count] [--legends] [--raw]

Reads the project URL and public anon key from scripts/net/cloud_config.gd and prints one line per
fight: outcome, legend, the pack (level, row, HP left, damage dealt/taken, knocked out), rounds per
wave and how far the legend was worn down. --raw prints the reports as JSON instead.
"""
import json
import re
import sys
import urllib.request
from pathlib import Path

CONFIG = Path(__file__).resolve().parent.parent / "scripts" / "net" / "cloud_config.gd"


def setting(text: str, name: str) -> str:
    match = re.search(r'const %s := "([^"]*)"' % name, text)
    return match.group(1) if match else ""


def fetch(count: int, legends: bool) -> list:
    text = CONFIG.read_text(encoding="utf-8")
    url, key = setting(text, "URL").rstrip("/"), setting(text, "ANON_KEY")
    request = urllib.request.Request(
        url + "/rest/v1/rpc/recent_battles",
        data=json.dumps({"p_limit": count, "p_legends": legends}).encode(),
        headers={"apikey": key, "Authorization": "Bearer " + key, "Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def unit(u: dict) -> str:
    down = " KO" if u.get("down") else ""
    return "%s L%d %s %d/%d hp, dealt %d took %d%s" % (
        u["id"], u["lvl"], u["row"][0].upper(), u["hp"], u["max_hp"], u["dealt"], u["taken"], down)


def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    rows = fetch(int(args[0]) if args else 50, "--legends" in sys.argv)
    if "--raw" in sys.argv:
        print(json.dumps(rows, indent=2))
        return
    for row in rows:
        r = row["report"]
        print("%s  %-8s %-18s players %d  threat %s  mult %.2f  rounds %s%s" % (
            row["created_at"][:16], r["outcome"], row["legend"] or r.get("territory", "patrol"),
            row["players"], r.get("threat", "?"), r["zombie_mult"], r["rounds"], "  AUTO" if r.get("auto") else ""))
        for u in r["pack"]:
            print("    " + unit(u))
        for z in r["legends"]:
            print("    LEGEND %s: %d/%d hp left, atk %d def %d, dealt %d" % (
                z["id"], z["hp"], z["max_hp"], z["atk"], z["def"], z["dealt"]))


if __name__ == "__main__":
    main()
