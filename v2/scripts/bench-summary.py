#!/usr/bin/env python3
"""Summarises bench-{android,ios}.sh runs: Markdown tables and a JSON file.

For each platform, device, preset and cache state, the median and P95 of
each metric per library across iterations, and for each metric a verdict of
TurboImage ("turbo") against every other library in the run (`expo`, the
default expo-image; `expoMem`, with its memory cache on; `rn`):

  faster / slower / less / more   two-sided exact Mann-Whitney U test with
                                  p < 0.05 AND medians more than 5% apart
  no significant difference      otherwise (including too few runs: with 5
                                  runs each, p < 0.05 needs no overlap at
                                  all; with 3 each it is impossible)

Metrics are tagged by where they come from: "direct" (measured as is),
"derived" (computed from direct ones). See
docs/benchmark/BENCHMARK_METHODOLOGY.md.

Usage: python3 scripts/bench-summary.py <run.jsonl> [more.jsonl ...]
Writes <first run>.summary.json next to the first input.
"""

import itertools
import json
import math
import pathlib
import statistics
import sys
from collections import defaultdict

# name, how to read it from a run, unit, which way is better, origin.
METRICS = [
    ("firstMs", lambda r: r["app"].get("firstMs"), "ms", "lower", "direct"),
    ("p50Ms", lambda r: r["app"].get("p50Ms"), "ms", "lower", "direct"),
    ("p95Ms", lambda r: r["app"].get("p95Ms"), "ms", "lower", "direct"),
    ("lastMs", lambda r: r["app"].get("lastMs"), "ms", "lower", "direct"),
    ("latencyP50Ms", lambda r: r["app"].get("latencyP50Ms"), "ms", "lower", "direct"),
    ("latencyP95Ms", lambda r: r["app"].get("latencyP95Ms"), "ms", "lower", "direct"),
    ("firstScreenMs", lambda r: r["app"].get("firstScreenMs"), "ms", "lower", "direct"),
    ("lastScreenMs", lambda r: r["app"].get("lastScreenMs"), "ms", "lower", "direct"),
    ("failed", lambda r: r["app"].get("failed"), "", "lower", "direct"),
    ("requests", lambda r: delta(r, "count"), "", "lower", "direct"),
    ("aborted", lambda r: delta(r, "aborted"), "", None, "direct"),
    ("servedWithoutRequestPct", lambda r: served_without_request(r), "%", None, "derived"),
    ("peakMemMb", lambda r: kb_to_mb((r.get("memory") or {}).get("peakKb")), "MB", "lower", "direct"),
    ("endMemMb", lambda r: kb_to_mb((r.get("memory") or {}).get("endKb")), "MB", "lower", "direct"),
    ("jankyPct", lambda r: janky_pct(r), "%", "lower", "derived"),
    ("frameP95Ms", lambda r: (r.get("gfx") or {}).get("p95Ms"), "ms", "lower", "direct"),
]

# Smaller than this relative difference of medians is never called a win.
MIN_EFFECT = 0.05
ALPHA = 0.05


def delta(row, key):
    before, after = row.get("serverBefore") or {}, row.get("serverAfter") or {}
    if before.get(key) is None or after.get(key) is None:
        return None
    return after[key] - before[key]


def served_without_request(row):
    """Share of loaded images that caused no request: memory and disk cache
    hits and coalesced loads together. Derived; meaningless for `cancel`."""
    loaded, requests = row["app"].get("loaded"), delta(row, "count")
    if not loaded or requests is None:
        return None
    return max(0.0, 100.0 * (1 - requests / loaded))


def janky_pct(row):
    gfx = row.get("gfx")
    if not gfx or not gfx.get("frames"):
        return None
    return 100.0 * gfx["janky"] / gfx["frames"]


def kb_to_mb(kb):
    return None if kb is None else kb / 1024


def nearest_rank(values, q):
    values = sorted(values)
    return values[min(len(values) - 1, max(0, math.ceil(q * len(values)) - 1))]


def mann_whitney_p(x, y):
    """Two-sided exact permutation p-value of the U statistic (mid-ranks for
    ties). Normal approximation above 200k permutations."""
    n1, n2 = len(x), len(y)
    if n1 < 2 or n2 < 2:
        return None
    pooled = x + y
    order = sorted(range(len(pooled)), key=lambda i: pooled[i])
    ranks = [0.0] * len(pooled)
    i = 0
    while i < len(order):
        j = i
        while j + 1 < len(order) and pooled[order[j + 1]] == pooled[order[i]]:
            j += 1
        for k in range(i, j + 1):
            ranks[order[k]] = (i + j) / 2 + 1
        i = j + 1
    mean_u = n1 * n2 / 2

    def u_of(indices):
        return sum(ranks[k] for k in indices) - n1 * (n1 + 1) / 2

    observed = abs(u_of(range(n1)) - mean_u)
    if math.comb(n1 + n2, n1) <= 200_000:
        total = extreme = 0
        for combo in itertools.combinations(range(n1 + n2), n1):
            total += 1
            if abs(u_of(combo) - mean_u) >= observed - 1e-9:
                extreme += 1
        return extreme / total
    sd = math.sqrt(n1 * n2 * (n1 + n2 + 1) / 12)
    return math.erfc(observed / sd / math.sqrt(2)) if sd else 1.0


def verdict(turbo, other, better):
    """TurboImage compared with another library on one metric."""
    if len(turbo) < 2 or len(other) < 2:
        return "too few runs", None
    p = mann_whitney_p(turbo, other)
    mt, me = statistics.median(turbo), statistics.median(other)
    scale = max(abs(mt), abs(me))
    effect = abs(mt - me) / scale if scale else 0.0
    if p is None or p >= ALPHA or effect <= MIN_EFFECT:
        return "no significant difference", p
    turbo_lower = mt < me
    if better is None:
        return ("turbo lower" if turbo_lower else "turbo higher"), p
    turbo_better = turbo_lower if better == "lower" else not turbo_lower
    return ("turbo better" if turbo_better else "turbo worse"), p


def fmt(value, unit=""):
    if value is None:
        return "–"
    if isinstance(value, float) and not value.is_integer():
        return f"{value:.1f}{unit}"
    return f"{int(value)}{unit}"


def main(paths):
    rows = []
    for path in paths:
        with open(path) as lines:
            rows.extend(json.loads(line) for line in lines if line.strip())

    groups = defaultdict(lambda: defaultdict(list))
    for row in rows:
        device = row.get("device") or {}
        key = (row["platform"], device.get("model", "?"), row["preset"], row["cache"])
        groups[key][row["lib"]].append(row)

    summary = []
    for (platform, model, preset, cache), by_lib in sorted(groups.items()):
        print(f"\n### {platform} · {model} · {preset} · {cache}\n")
        present = [
            m for m in METRICS if any(m[1](r) is not None for rs in by_lib.values() for r in rs)
        ]
        rivals = [lib for lib in sorted(by_lib) if lib != "turbo"] if "turbo" in by_lib else []
        print(
            "| metric | origin | "
            + " | ".join(f"{lib} median (P95)" for lib in sorted(by_lib))
            + "".join(f" | turbo vs {lib} (p)" for lib in rivals)
            + " |"
        )
        print("|" + "---|" * (len(by_lib) + 2 + len(rivals)))
        group = {
            "platform": platform,
            "device": model,
            "preset": preset,
            "cache": cache,
            "runs": {lib: len(rs) for lib, rs in by_lib.items()},
            "timedOut": {lib: sum(1 for r in rs if r["app"].get("timedOut")) for lib, rs in by_lib.items()},
            "metrics": {},
        }
        for name, read, unit, better, origin in present:
            values = {
                lib: [v for v in (read(r) for r in rs) if v is not None] for lib, rs in by_lib.items()
            }
            cells, stats = [], {}
            for lib in sorted(by_lib):
                vs = values[lib]
                if vs:
                    med, p95 = statistics.median(vs), nearest_rank(vs, 0.95)
                    stats[lib] = {"median": med, "p95": p95, "n": len(vs), "values": vs}
                    cells.append(f"{fmt(med, unit)} ({fmt(p95, unit)})")
                else:
                    cells.append("–")
            verdicts = {}
            for lib in rivals:
                if values.get("turbo") and values.get(lib):
                    result, p = verdict(values["turbo"], values[lib], better)
                else:
                    result, p = "–", None
                verdicts[lib] = {"verdict": result, "p": p}
                cells.append(f"{result} ({'–' if p is None else f'{p:.3f}'})")
            group["metrics"][name] = {
                "unit": unit,
                "origin": origin,
                "better": better,
                "stats": stats,
                "vsTurbo": verdicts,
            }
            print(f"| {name} | {origin} | " + " | ".join(cells) + " |")
        timed_out = {lib: n for lib, n in group["timedOut"].items() if n}
        runs = ", ".join(f"{lib} {n}" for lib, n in sorted(group["runs"].items()))
        print(f"\nRuns: {runs}." + (f" Timed out: {timed_out}." if timed_out else ""))
        summary.append(group)

    out = pathlib.Path(paths[0]).with_suffix(".summary.json")
    out.write_text(json.dumps(summary, indent=2) + "\n")
    print(f"\nsummary written to {out}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    main(sys.argv[1:])
