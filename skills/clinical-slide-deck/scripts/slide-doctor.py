#!/usr/bin/env python3
"""
slide-doctor.py — Automated integrity checker for Hermes slide deck HTML.

Checks:
  1. Overall div balance (<div> vs </div>)
  2. Per-slide div balance (via <!-- SLIDE marker splitting)
  3. Tag-type balance (table, ul, ol)
  4. Sequential data-slide numbering (1..N)
  5. Orphaned content between slides
  6. SVG marker defs placement

Usage:
  python3 slide-doctor.py deck.html
  python3 slide-doctor.py deck.html --json    # machine-readable output
  python3 slide-doctor.py deck.html --fix     # attempt auto-repair

Exit code: 0 = clean, 1 = issues found, 2 = fatal error
"""

import re
import sys
import json
import argparse
from pathlib import Path


def check_div_balance(html):
    opens = len(re.findall(r'<div\b', html))
    closes = len(re.findall(r'</div>', html))
    return opens, closes, opens - closes


def check_tag_balance(html, tag):
    opens = len(re.findall(f'<{tag}\\b', html))
    closes = len(re.findall(f'</{tag}>', html))
    return opens, closes, opens - closes


def check_data_slide_sequence(html):
    values = [int(x) for x in re.findall(r'data-slide="(\d+)"', html)]
    if not values:
        return values, False, "No data-slide attributes found"
    expected = list(range(1, len(values) + 1))
    if values != expected:
        missing = set(expected) - set(values)
        extra = set(values) - set(expected)
        return values, False, f"Gaps: missing={sorted(missing)}, extra={sorted(extra)}"
    return values, True, "Sequential 1..{}".format(len(values))


def check_per_slide_divs(html):
    markers = list(re.finditer(r'<!--\s*SLIDE\s+(?:\d+|###)', html))
    issues = []
    for i, m in enumerate(markers):
        start = m.start()
        if i+1 < len(markers):
            end = markers[i+1].start()
        else:
            # Last slide: stop at </div><!-- /slides --> if present
            slides_close = html.find('</div><!-- /slides -->', start)
            end = slides_close if slides_close != -1 else len(html)
        block = html[start:end]
        opens = len(re.findall(r'<div\b', block))
        closes = len(re.findall(r'</div>', block))
        if opens != closes:
            ds = re.search(r'data-slide="(\d+)"', block)
            sid = ds.group(1) if ds else re.search(r'SLIDE\s+(\S+)', block).group(1)
            issues.append({"slide": sid, "opens": opens, "closes": closes, "delta": opens - closes})
    return issues


def check_orphaned_content(html):
    markers = list(re.finditer(r'<!--\s*SLIDE\s+(?:\d+|###)', html))
    orphans = []
    for i in range(len(markers) - 1):
        curr_start = markers[i].start()
        next_start = markers[i+1].start()
        block = html[curr_start:next_start]
        # Remove the comment marker
        block_no_comment = re.sub(r'<!--.*?-->', '', block, flags=re.DOTALL)
        # Find the last </div> that closes the slide
        last_close = block_no_comment.rfind('</div>')
        if last_close > 0:
            after = block_no_comment[last_close+6:].strip()
            if after:
                curr_id = re.search(r'SLIDE\s+(\S+)', html[curr_start:curr_start+50])
                sid = curr_id.group(1) if curr_id else "?"
                orphans.append({"after_slide": sid, "content_preview": after[:80]})
    return orphans


def check_svg_markers(html):
    """Check SVG marker defs are placed before references."""
    svgs = []
    for m in re.finditer(r'<svg[\s\S]*?</svg>', html):
        svg = m.group(0)
        refs_marker = 'marker-end="url(#' in svg
        has_top_marker = False
        bottom_marker = False
        if refs_marker:
            # Check if marker is in first defs block
            first_defs = re.search(r'<defs>(.*?)</defs>', svg, re.DOTALL)
            if first_defs and '<marker' in first_defs.group(1):
                has_top_marker = True
            # Check if marker is in last defs block (after content)
            last_defs = list(re.finditer(r'<defs>.*?</defs>', svg, re.DOTALL))
            if len(last_defs) > 1:
                last_content = last_defs[-1].group(0)
                if '<marker' in last_content:
                    # Check if any marker-end references appear before this defs
                    last_defs_pos = last_defs[-1].start()
                    refs_before = 'marker-end="url(#' in svg[:last_defs_pos]
                    if refs_before:
                        bottom_marker = True
        if refs_marker and (not has_top_marker or bottom_marker):
            svgs.append({"has_top_marker": has_top_marker, "bottom_marker": bottom_marker,
                         "preview": svg[:80]})
    return svgs


def auto_fix(html, issues):
    """Attempt auto-repair for common issues."""
    fixed = html
    # Fix tag mismatches (table closed with ul)
    # Scan for <table> that's followed by </ul>
    for tag in ['table', 'ul', 'ol']:
        opens = len(re.findall(f'<{tag}\\b', fixed))
        closes = len(re.findall(f'</{tag}>', fixed))
        if opens != closes:
            # Can't auto-fix tag mismatches safely
            pass
    return fixed


def main():
    parser = argparse.ArgumentParser(description="Slide deck HTML integrity checker")
    parser.add_argument("path", help="Path to HTML file")
    parser.add_argument("--json", action="store_true", help="Machine-readable JSON output")
    parser.add_argument("--agent", action="store_true", help="Minimal agent-optimized output")
    parser.add_argument("--fix", action="store_true", help="Attempt auto-repair")
    args = parser.parse_args()

    path = Path(args.path)
    if not path.exists():
        print(f"ERROR: {path} not found", file=sys.stderr)
        sys.exit(2)

    html = path.read_text(encoding="utf-8")
    results = {"file": str(path), "checks": {}}

    # Check 1: Overall div balance
    opens, closes, delta = check_div_balance(html)
    results["checks"]["div_balance"] = {"opens": opens, "closes": closes, "delta": delta, "ok": delta == 0}

    # Check 2: Tag-type balance
    tag_results = {}
    for tag in ['table', 'ul', 'ol']:
        to, tc, td = check_tag_balance(html, tag)
        tag_results[tag] = {"opens": to, "closes": tc, "delta": td, "ok": td == 0}
    results["checks"]["tag_balance"] = tag_results

    # Check 3: data-slide sequence
    values, ok, msg = check_data_slide_sequence(html)
    results["checks"]["data_slide_sequence"] = {"count": len(values), "ok": ok, "message": msg}

    # Check 4: Per-slide div balance
    per_slide = check_per_slide_divs(html)
    results["checks"]["per_slide_divs"] = {"issues": len(per_slide), "details": per_slide, "ok": len(per_slide) == 0}

    # Check 5: Orphaned content
    orphans = check_orphaned_content(html)
    results["checks"]["orphaned_content"] = {"issues": len(orphans), "details": orphans, "ok": len(orphans) == 0}

    # Check 6: SVG markers
    svg_issues = check_svg_markers(html)
    results["checks"]["svg_markers"] = {"issues": len(svg_issues), "details": svg_issues, "ok": len(svg_issues) == 0}

    # Overall verdict
    all_ok = all(c.get("ok", True) for c in results["checks"].values()
                 if isinstance(c, dict) and "ok" in c)
    # Also check nested dicts like tag_balance
    for tag, info in tag_results.items():
        if not info["ok"]:
            all_ok = False

    results["ok"] = all_ok

    if args.json or args.agent:
        out = {"ok": all_ok, "file": str(path), "issues": []}
        if not all_ok:
            for check_name, check_data in d.items():
                if isinstance(check_data, dict) and not check_data.get("ok", True):
                    out["issues"].append({check_name: check_data.get("details", "failed")})
            for tag, info in d.get("tag_balance", {}).items():
                if not info["ok"]:
                    out["issues"].append({"tag_mismatch": {tag: f"{info['opens']}/{info['closes']}"}})
        if args.agent:
            # Minimal: one line per issue
            if out["issues"]:
                for issue in out["issues"]:
                    print(json.dumps(issue))
            else:
                print(json.dumps({"ok": True, "file": str(path)}))
        else:
            print(json.dumps(out, indent=2))
    else:
        # Human-readable output
        d = results["checks"]
        print(f"slide-doctor: {path.name}")
        print(f"  div balance:  {d['div_balance']['opens']}/{d['div_balance']['closes']} "
              f"(delta={d['div_balance']['delta']}) {'✓' if d['div_balance']['ok'] else '✗'}")
        for tag, info in d['tag_balance'].items():
            print(f"  {tag:7s}:     {info['opens']}/{info['closes']} "
                  f"(delta={info['delta']}) {'✓' if info['ok'] else '✗'}")
        print(f"  data-slide:   {d['data_slide_sequence']['message']} "
              f"{'✓' if d['data_slide_sequence']['ok'] else '✗'}")
        print(f"  per-slide:    {d['per_slide_divs']['issues']} imbalanced "
              f"{'✓' if d['per_slide_divs']['ok'] else '✗'}")
        if d['per_slide_divs']['details']:
            for issue in d['per_slide_divs']['details']:
                print(f"    slide {issue['slide']}: {issue['opens']} opens, {issue['closes']} closes")
        print(f"  orphans:      {d['orphaned_content']['issues']} blocks "
              f"{'✓' if d['orphaned_content']['ok'] else '✗'}")
        if d['orphaned_content']['details']:
            for o in d['orphaned_content']['details']:
                print(f"    after slide {o['after_slide']}: {o['content_preview'][:60]}")
        print(f"  svg markers:  {d['svg_markers']['issues']} misplaced "
              f"{'✓' if d['svg_markers']['ok'] else '✗'}")
        if d['svg_markers']['details']:
            for s in d['svg_markers']['details']:
                status = []
                if not s['has_top_marker']: status.append("marker missing from top defs")
                if s['bottom_marker']: status.append("marker in bottom defs (after refs)")
                print(f"    {', '.join(status)}")

        verdict = "✓ ALL CLEAN" if all_ok else "✗ ISSUES FOUND"
        print(f"\n  {verdict}")

    # Auto-fix
    if args.fix and not all_ok:
        fixed_html = auto_fix(html, results)
        fix_path = path.with_suffix(".fixed.html")
        fix_path.write_text(fixed_html, encoding="utf-8")
        print(f"\n  Auto-fix written to: {fix_path}")

    sys.exit(0 if all_ok else 1)


if __name__ == "__main__":
    main()
