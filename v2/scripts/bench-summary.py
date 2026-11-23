#!/usr/bin/env python3
"""Summarises a benchmark run from scripts/bench-android.sh as Markdown.

One table per scenario, source and cache state, one row per library, with
the median over iterations of each metric. Medians rather than means: a
single run disturbed by the OS (a GC, a background job) should not move the
result.

Usage: python3 scripts/bench-summary.py tmp/bench/android-<timestamp>.jsonl
"""

import json
import statistics
import sys
from collections import defaultdict


def median(values):
    values = [v for v in values if v is not None]
    return statistics.median(values) if values else None


def fmt(value, unit=""):
    if value is None:
        return "–"
    if isinstance(value, float) and not value.is_integer():
        return f"{value:.1f}{unit}"
    return f"{int(value)}{unit}"


def main(path):
    groups = defaultdict(list)
    with open(path) as lines:
        for line in lines:
            row = json.loads(line)
            app = row["app"]
            groups[(app["scenario"], app["source"], row["cache"])].append(row)

    for (scenario, source, cache), rows in sorted(groups.items()):
        by_lib = defaultdict(list)
        for row in rows:
            by_lib[row["app"]["lib"]].append(row)

        print(f"\n### {scenario} · {source} · {cache}  (median of runs)\n")
        # Load times are from mount, which for `load` is when every request
        # starts. In `grid` most images mount only as the list scrolls to
        # them, so their time from mount is mostly scroll position; the grid
        # table shows the first screen's time, frames and memory instead.
        # TODO: per-image latency (load start to success) for `grid`, from
        # each library's start event.
        header = ["lib", "runs", "failed", "first", "PSS"]
        if scenario == "load":
            header[4:4] = ["p50 load", "p90 load", "last load"]
        else:
            header += ["frames", "janky %", "p90 frame", "p99 frame"]
        print("| " + " | ".join(header) + " |")
        print("|" + "---|" * len(header))

        for lib, lib_rows in sorted(by_lib.items()):
            app = [r["app"] for r in lib_rows]
            cells = [
                lib,
                str(len(lib_rows)),
                fmt(sum(a["failed"] for a in app)),
                fmt(median(a["firstMs"] for a in app), " ms"),
                fmt(median(r["pssKb"] / 1024 if r["pssKb"] else None for r in lib_rows), " MB"),
            ]
            if scenario == "load":
                cells[4:4] = [
                    fmt(median(a["p50Ms"] for a in app), " ms"),
                    fmt(median(a["p90Ms"] for a in app), " ms"),
                    fmt(median(a["lastMs"] for a in app), " ms"),
                ]
            else:
                gfx = [r["gfx"] for r in lib_rows if r["gfx"]]
                cells += [
                    fmt(median(g["frames"] for g in gfx)),
                    fmt(median(100 * g["janky"] / g["frames"] if g["frames"] else None for g in gfx), "%"),
                    fmt(median(g["p90Ms"] for g in gfx), " ms"),
                    fmt(median(g["p99Ms"] for g in gfx), " ms"),
                ]
            print("| " + " | ".join(cells) + " |")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
