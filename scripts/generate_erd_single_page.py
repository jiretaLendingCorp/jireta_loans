#!/usr/bin/env python3
"""Single-page continuous ERD for the Jireta Loans Supabase schema.

Nothing is split into per-domain pages: the whole schema lives on one canvas,
laid out as a layered DAG (parents above, children below) so every foreign key
can be traced from its column to the table it points at.

Pipeline: schema (from generate_erd_pdf) -> layered layout -> giant SVG -> HTML -> Chrome PDF

Usage:
    python scripts/generate_erd_single_page.py [--out <pdf>] [--html <html>] [--png-debug]
"""

from __future__ import annotations

import argparse
import math
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import generate_erd_pdf as base  # noqa: E402

TABLES = base.TABLES
RELATIONS = base.RELATIONS
GROUPS = base.GROUPS

# ---- geometry -----------------------------------------------------------------------
MARGIN_X = 90
HDR_BAND = 150
FOOT_BAND = 70
GAP_Y = 190          # vertical channel between two layers (edge lanes live here)
GAP_X = 44           # horizontal gutter between boxes inside a layer
VNODE_W = 10         # virtual node slot width for long edges
EXTRA_GAP_MAX = 90   # how much a layer may spread out
LANES = 10

# ---- palette ------------------------------------------------------------------------
INK = "#0f172a"


def metrics(name):
    w, h, shown, hidden = base.table_metrics(name)
    return w, h, shown, hidden


# =====================================================================================
# Graph
# =====================================================================================
def build_edges():
    edges = []
    for child, ccol, parent, pcol, o2o in RELATIONS:
        edges.append({"child": child, "ccol": ccol, "parent": parent, "pcol": pcol,
                      "o2o": o2o, "idx": len(edges)})
    return edges


def assign_layers(edges):
    """layer(child) = 1 + max(layer(parent)); self-loops ignored, cycles broken.

    Audit columns (created_by / approved_by / reviewed_by …) are soft pointers to
    users and are deliberately left out of the layering: including them creates
    fake cycles (roles.archived_by -> users, users.role_id -> roles) and would
    stack half the schema in the wrong direction. They are still drawn.
    """
    parents = {t: set() for t in TABLES}
    for e in edges:
        if e["child"] == e["parent"] or e["ccol"].endswith("_by"):
            continue
        parents[e["child"]].add(e["parent"])

    layer = {}
    # iterative longest-path with cycle protection
    visiting = set()

    def depth(node):
        if node in layer:
            return layer[node]
        if node in visiting:          # cycle -> treat as root of the break
            return 0
        visiting.add(node)
        d = 0
        for p in parents[node]:
            d = max(d, depth(p) + 1)
        visiting.discard(node)
        layer[node] = d
        return d

    for t in TABLES:
        depth(t)
    return layer, parents


# =====================================================================================
# Layout
# =====================================================================================
class Item:
    __slots__ = ("id", "kind", "table", "w", "h", "layer", "order", "x", "y", "shown", "hidden")

    def __init__(self, iid, kind, table, w, h, layer, shown=None, hidden=0):
        self.id, self.kind, self.table = iid, kind, table
        self.w, self.h, self.layer = w, h, layer
        self.order = 0
        self.x = 0.0
        self.y = 0.0
        self.shown = shown
        self.hidden = hidden


def layout():
    edges = build_edges()
    layer_of, parents = assign_layers(edges)

    max_layer = max(layer_of.values())
    items: dict[str, Item] = {}
    layers: list[list[Item]] = [[] for _ in range(max_layer + 1)]

    domain_rank = {g: i for i, g in enumerate(GROUPS)}

    for name in base.TABLE_ORDER:
        w, h, shown, hidden = metrics(name)
        it = Item(name, "table", name, w, h, layer_of[name], shown, hidden)
        items[name] = it
        layers[it.layer].append(it)

    # ---- virtual nodes for edges that skip layers -----------------------------------
    # chain is ordered from the child side towards the parent side; it also
    # records whether the edge climbs (parent above) or drops (parent below).
    for e in edges:
        e["chain"] = []
        c, p = layer_of[e["child"]], layer_of[e["parent"]]
        e["dir"] = 0 if c == p else (-1 if p < c else 1)   # -1 = rises, +1 = drops
        if e["child"] == e["parent"] or abs(c - p) <= 1:
            continue
        span = range(c - 1, p, -1) if e["dir"] < 0 else range(c + 1, p)
        for k in span:
            vid = f"v{e['idx']}_{k}"
            v = Item(vid, "virt", e["parent"], VNODE_W, 0, k)
            items[vid] = v
            layers[k].append(v)
            e["chain"].append(vid)

    # ---- initial order: domain clusters, then name -----------------------------------
    for lst in layers:
        lst.sort(key=lambda it: (domain_rank[TABLES[it.table]["group"]]
                                 if it.kind == "table" else 99,
                                 it.table if it.kind == "table" else it.id))
        for i, it in enumerate(lst):
            it.order = i

    # ---- adjacency between consecutive sequence positions ----------------------------
    neighbours = {iid: set() for iid in items}
    for e in edges:
        if e["child"] == e["parent"]:
            continue
        seq = [e["child"]] + e["chain"] + [e["parent"]]
        for a, b in zip(seq, seq[1:]):
            neighbours[a].add(b)
            neighbours[b].add(a)

    def sweep(l, ref):
        vals = {}
        for it in layers[l]:
            nb = [items[n].order for n in neighbours[it.id] if items[n].layer == ref]
            vals[it.id] = (sum(nb) / len(nb)) if nb else float(it.order)
        layers[l].sort(key=lambda it: (vals[it.id], it.order))
        for i, it in enumerate(layers[l]):
            it.order = i

    for _ in range(8):
        for l in range(1, len(layers)):
            sweep(l, l - 1)
        for l in range(len(layers) - 2, -1, -1):
            sweep(l, l + 1)

    # ---- horizontal geometry ---------------------------------------------------------
    def layer_width(lst, gap):
        return sum(it.w for it in lst) + gap * max(0, len(lst) - 1)

    widest = max(layer_width(lst, GAP_X) for lst in layers)
    canvas_w = widest + 2 * MARGIN_X
    content_w = canvas_w - 2 * MARGIN_X

    for lst in layers:
        n = len(lst)
        if n == 0:
            continue
        gap = GAP_X
        if n > 1:
            spare = content_w - sum(it.w for it in lst)
            if spare > GAP_X * (n - 1):
                gap = min(GAP_X + EXTRA_GAP_MAX, spare / (n - 1))
        total = layer_width(lst, gap)
        x = MARGIN_X + (content_w - total) / 2
        for it in lst:
            it.x = x
            x += it.w + gap

    # ---- vertical geometry -----------------------------------------------------------
    layer_h = [max((it.h for it in lst), default=0) for lst in layers]
    layer_top = []
    y = HDR_BAND
    for l, h in enumerate(layer_h):
        if l:
            y += GAP_Y
        layer_top.append(y)
        y += h
    content_bottom = y
    canvas_h = content_bottom + FOOT_BAND

    for it in items.values():
        it.y = layer_top[it.layer]

    # ---- alignment passes (median of neighbours, order-preserving) -------------------
    def clamp_layer(l):
        lst = layers[l]
        for i, it in enumerate(lst):
            nb = [items[n].x + items[n].w / 2 for n in neighbours[it.id]
                  if items[n].layer in (l - 1, l + 1)]
            if nb:
                nb.sort()
                m = nb[len(nb) // 2]
                want = m - it.w / 2
                lo = (lst[i - 1].x + lst[i - 1].w + GAP_X) if i else MARGIN_X
                hi = (lst[i + 1].x - it.w - GAP_X) if i + 1 < len(lst) else canvas_w - MARGIN_X - it.w
                it.x = min(max(want, lo), max(lo, hi))

    for _ in range(6):
        for l in range(1, len(layers)):
            clamp_layer(l)
        for l in range(len(layers) - 2, -1, -1):
            clamp_layer(l)

    return edges, items, layers, layer_top, layer_h, canvas_w, canvas_h


# =====================================================================================
# Rendering
# =====================================================================================
def rounded_path(points, r=14.0):
    if len(points) < 2:
        return ""
    d = [f"M{points[0][0]:.1f},{points[0][1]:.1f}"]
    for i in range(1, len(points) - 1):
        p0, p1, p2 = points[i - 1], points[i], points[i + 1]
        v1 = (p1[0] - p0[0], p1[1] - p0[1])
        v2 = (p2[0] - p1[0], p2[1] - p1[1])
        l1 = math.hypot(*v1) or 1.0
        l2 = math.hypot(*v2) or 1.0
        rr = min(r, l1 / 2, l2 / 2)
        a = (p1[0] - v1[0] / l1 * rr, p1[1] - v1[1] / l1 * rr)
        b = (p1[0] + v2[0] / l2 * rr, p1[1] + v2[1] / l2 * rr)
        d.append(f"L{a[0]:.1f},{a[1]:.1f} Q{p1[0]:.1f},{p1[1]:.1f} {b[0]:.1f},{b[1]:.1f}")
    d.append(f"L{points[-1][0]:.1f},{points[-1][1]:.1f}")
    return " ".join(d)


def anchor_slots(edges, items):
    """Spread the edges leaving / entering a box across its top / bottom edge."""
    out, inc = {}, {}
    for e in edges:
        if e["child"] != e["parent"]:
            out.setdefault(e["child"], []).append(e)
            inc.setdefault(e["parent"], []).append(e)
    slots = {}

    def spread(bucket, key):
        lst = bucket.get(key, [])
        it = items[key]
        n = len(lst)
        for i, e in enumerate(lst):
            frac = (i + 1) / (n + 1)
            slots[(key, id(e))] = it.x + it.w * (0.14 + 0.72 * frac)
        return lst

    for child in out:
        spread(out, child)
    for parent in inc:
        spread(inc, parent)
    return slots


def edge_color(e):
    return GROUPS[TABLES[e["parent"]]["group"]][1]


def edge_marker(e):
    return f'url(#arrow-{TABLES[e["parent"]]["group"]})'


def lane_offset(e):
    lane = e["idx"] % LANES
    return lane, (lane - (LANES - 1) / 2) * (GAP_Y * 0.72 / LANES)


def edge_points(e, items, slots, layer_top):
    """Orthogonal polyline from the child row to the parent row.

    gapy(k) is the horizontal channel immediately above layer k's band; every
    horizontal run therefore happens in a gutter, and every vertical run passes
    through a virtual-node slot, so a line never rides over a table box.
    """
    child, parent = items[e["child"]], items[e["parent"]]
    if child is parent:
        return None
    x1 = slots[(e["child"], id(e))]
    x2 = slots[(e["parent"], id(e))]
    _, dy = lane_offset(e)

    def gapy(l):
        return layer_top[l] - GAP_Y / 2 + dy

    c, p, d = child.layer, parent.layer, e["dir"]
    if d < 0:                                    # parent sits above the child
        pts = [(x1, child.y), (x1, gapy(c))]
        for vid in e["chain"]:
            v = items[vid]
            vx = v.x + v.w / 2
            pts.append((vx, gapy(v.layer + 1)))
            pts.append((vx, gapy(v.layer)))
        pts.append((x2, gapy(p + 1)))
        pts.append((x2, parent.y + parent.h))
    else:                                        # parent sits below the child
        pts = [(x1, child.y + child.h), (x1, gapy(c + 1))]
        for vid in e["chain"]:
            v = items[vid]
            vx = v.x + v.w / 2
            pts.append((vx, gapy(v.layer)))
            pts.append((vx, gapy(v.layer + 1)))
        pts.append((x2, gapy(p)))
        pts.append((x2, parent.y))
    return pts


def render_edge(e, items, slots, layer_top, layer_h):
    child, parent = items[e["child"]], items[e["parent"]]
    if child is parent:                       # self reference
        x = child.x
        y = child.y + 42
        color = edge_color(e)
        return (f'<path d="M{x:.1f},{y:.1f} C{x - 46:.1f},{y:.1f} {x - 46:.1f},{y + 34:.1f} '
                f'{x:.1f},{y + 34:.1f}" fill="none" stroke="{color}" stroke-width="1.3" '
                f'opacity="0.75" marker-end="{edge_marker(e)}"/>'
                f'<text x="{x - 52:.1f}" y="{y + 20:.1f}" fill="{color}" font-size="10" '
                f'font-weight="700" font-family="Segoe UI,Arial" text-anchor="end">self</text>')

    color = edge_color(e)
    x1 = slots[(e["child"], id(e))]
    x2 = slots[(e["parent"], id(e))]
    pts = edge_points(e, items, slots, layer_top)

    d = rounded_path(pts)
    if e["dir"] < 0:
        label1 = f'<text x="{x1 + 5:.1f}" y="{child.y - 7:.1f}" fill="{color}" font-size="9.5" ' \
                 f'font-weight="700" font-family="Segoe UI,Arial">{"1" if e["o2o"] else "N"}</text>'
        label2 = f'<text x="{x2 - 5:.1f}" y="{parent.y + parent.h + 13:.1f}" fill="{color}" ' \
                 f'font-size="9.5" font-weight="700" font-family="Segoe UI,Arial" ' \
                 f'text-anchor="end">1</text>'
    else:
        label1 = f'<text x="{x1 + 5:.1f}" y="{child.y + child.h + 13:.1f}" fill="{color}" ' \
                 f'font-size="9.5" font-weight="700" font-family="Segoe UI,Arial">' \
                 f'{"1" if e["o2o"] else "N"}</text>'
        label2 = f'<text x="{x2 - 5:.1f}" y="{parent.y - 7:.1f}" fill="{color}" ' \
                 f'font-size="9.5" font-weight="700" font-family="Segoe UI,Arial" ' \
                 f'text-anchor="end">1</text>'
    return (f'<path d="{d}" fill="none" stroke="#ffffff" stroke-width="3.4" opacity="0.95"/>'
            f'<path d="{d}" fill="none" stroke="{color}" stroke-width="1.25" opacity="0.72" '
            f'marker-end="{edge_marker(e)}"/>' + label1 + label2)


def render_header(canvas_w):
    g = GROUPS
    parts = [f'<rect x="0" y="0" width="{canvas_w}" height="{HDR_BAND - 26}" fill="{INK}"/>',
             f'<rect x="0" y="{HDR_BAND - 26}" width="{canvas_w}" height="4" fill="#be123c"/>',
             f'<text x="{MARGIN_X}" y="52" fill="#f8fafc" font-size="34" font-weight="800" '
             f'font-family="Segoe UI,Arial">Jireta Loans &amp; Credit Corp — Entity–Relationship Diagram</text>',
             f'<text x="{MARGIN_X}" y="82" fill="#94a3b8" font-size="15" font-family="Segoe UI,Arial">'
             f'{len(TABLES)} tables · {len(RELATIONS)} foreign keys · complete schema on one canvas — '
             f'parents are drawn above their children, every arrow points at the table a column references.</text>']
    # legend row
    x = MARGIN_X
    y = 118
    parts.append(f'<text x="{x}" y="{y}" fill="#cbd5e1" font-size="12.5" font-family="Segoe UI,Arial">'
                 f'PK = primary key (red bar) · FK = foreign key (teal bar) · UQ = unique · '
                 f'arrow → parent row · "1" = one · "N" = many</text>')
    x = canvas_w - MARGIN_X
    for key in reversed(list(g)):
        label, stroke, fill, chip = g[key]
        tw = len(label) * 6.6 + 26
        x -= tw
        parts.append(f'<rect x="{x:.1f}" y="{y - 11}" width="14" height="12" rx="3" fill="{stroke}"/>')
        parts.append(f'<text x="{x + 19:.1f}" y="{y}" fill="#cbd5e1" font-size="12" '
                     f'font-family="Segoe UI,Arial">{base.esc(label)}</text>')
        x -= 14
    return "".join(parts)


def render_footer(canvas_w, canvas_h):
    return (f'<rect x="0" y="{canvas_h - FOOT_BAND + 24}" width="{canvas_w}" height="{FOOT_BAND - 24}" '
            f'fill="#f8fafc"/>'
            f'<line x1="{MARGIN_X}" y1="{canvas_h - FOOT_BAND + 24}" x2="{canvas_w - MARGIN_X}" '
            f'y2="{canvas_h - FOOT_BAND + 24}" stroke="#e2e8f0"/>'
            f'<text x="{MARGIN_X}" y="{canvas_h - 28}" fill="#64748b" font-size="12" '
            f'font-family="Segoe UI,Arial">Layout: layered DAG — reference tables and roles at the top, '
            f'operational tables below, so an arrow only ever points upward to its parent. '
            f'Relationships derived from the *_id / *_by conventions in supabase/migrations '
            f'(00109, 00110, 00128, 00130).</text>'
            f'<text x="{canvas_w - MARGIN_X}" y="{canvas_h - 28}" fill="#94a3b8" font-size="12" '
            f'text-anchor="end" font-family="Segoe UI,Arial">Generated {base.HDD} · one page, '
            f'nothing split</text>')


def build(canvas_w, canvas_h, edges, items, slots, layer_top, layer_h, layer_of):
    refs = {}
    for e in edges:
        refs[e["parent"]] = refs.get(e["parent"], 0) + 1
    parts = [render_header(canvas_w)]
    # layer guides
    for l, top in enumerate(layer_top):
        if l == 0:
            continue
        parts.append(f'<line x1="{MARGIN_X // 2}" y1="{top - GAP_Y / 2:.1f}" '
                     f'x2="{canvas_w - MARGIN_X // 2}" y2="{top - GAP_Y / 2:.1f}" '
                     f'stroke="#e2e8f0" stroke-width="1" stroke-dasharray="1 6"/>')
    for e in edges:
        parts.append(render_edge(e, items, slots, layer_top, layer_h))
    for it in items.values():
        if it.kind != "table":
            continue
        b = base.Box(it.table, it.x, it.y, it.w, it.h, it.shown, it.hidden,
                     TABLES[it.table]["tag"])
        b.refs = refs.get(it.table, 0)
        parts.append(base.render_box(b))
    parts.append(render_footer(canvas_w, canvas_h))
    return "".join(parts)


def svg_doc(canvas_w, canvas_h, body):
    markers = "".join(
        f'<marker id="arrow-{key}" viewBox="0 0 10 10" refX="8.5" refY="5" markerWidth="6" '
        f'markerHeight="6" orient="auto"><path d="M0,0.5 L9,5 L0,9.5 z" fill="{stroke}"/></marker>'
        for key, (label, stroke, fill, chip) in GROUPS.items())
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{canvas_w}" height="{canvas_h}" '
            f'viewBox="0 0 {canvas_w} {canvas_h}">'
            f'<defs>{markers}</defs>'
            f'<rect x="0" y="0" width="{canvas_w}" height="{canvas_h}" fill="#ffffff"/>'
            f'{body}</svg>')


def html_doc(canvas_w, canvas_h, svg):
    css = f"""
@page {{ size: {canvas_w / 96:.4f}in {canvas_h / 96:.4f}in; margin: 0; }}
html, body {{ margin: 0; padding: 0; background: #fff; }}
.page {{ width: {canvas_w}px; height: {canvas_h}px; overflow: hidden;
        -webkit-print-color-adjust: exact; print-color-adjust: exact; }}
svg {{ display: block; }}
"""
    return ("<!doctype html><html><head><meta charset='utf-8'>"
            "<title>Jireta Loans — ERD (full schema, one page)</title><style>" + css +
            "</style></head><body><div class='page'>" + svg + "</div></body></html>")


def count_edge_box_hits(edges, items, slots, layer_top):
    """How many edges pass over a box that is not one of their own endpoints."""
    rects = [(it.id, it.x, it.y, it.x + it.w, it.y + it.h)
             for it in items.values() if it.kind == "table"]
    bad = []
    for e in edges:
        pts = edge_points(e, items, slots, layer_top)
        if not pts:
            continue
        hits = set()
        for (ax, ay), (bx, by) in zip(pts, pts[1:]):
            steps = max(2, int(math.hypot(bx - ax, by - ay) // 5))
            for i in range(steps + 1):
                t = i / steps
                x, y = ax + (bx - ax) * t, ay + (by - ay) * t
                for name, x0, y0, x1, y1 in rects:
                    if name in (e["child"], e["parent"]):
                        continue
                    if x0 < x < x1 and y0 < y < y1:
                        hits.add(name)
        if hits:
            bad.append((e["child"], e["ccol"], e["parent"], sorted(hits)))
    return bad


def validate(items, layers, canvas_w, canvas_h):
    problems = []
    for l, lst in enumerate(layers):
        for a, b in zip(lst, lst[1:]):
            if a.x + a.w > b.x + 0.5:
                problems.append(f"layer {l}: {a.id} overlaps {b.id}")
        for it in lst:
            if it.x < MARGIN_X - 1 or it.x + it.w > canvas_w - MARGIN_X + 1:
                problems.append(f"layer {l}: {it.id} outside canvas ({it.x:.0f})")
            if it.y + it.h > canvas_h - FOOT_BAND + 1:
                problems.append(f"layer {l}: {it.id} below footer")
    for it in items.values():
        if it.kind != "table":
            continue
        for other in items.values():
            if other is it or other.kind != "table" or other.id < it.id:
                continue
            if (it.x < other.x + other.w and other.x < it.x + it.w and
                    it.y < other.y + other.h and other.y < it.y + it.h):
                problems.append(f"overlap {it.id} / {other.id}")
    return problems


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(os.path.expanduser("~"), "Desktop",
                                                 "jireta_loans_erd.pdf"))
    ap.add_argument("--html", default=os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                                  "..", "build", "erd", "erd_full.html"))
    ap.add_argument("--keep-html", action="store_true")
    args = ap.parse_args()

    edges, items, layers, layer_top, layer_h, canvas_w, canvas_h = layout()
    slots = anchor_slots(edges, items)
    layer_of = {it.id: it.layer for it in items.values()}

    problems = validate(items, layers, canvas_w, canvas_h)
    hits = count_edge_box_hits(edges, items, slots, layer_top)
    print(f"tables={len(TABLES)} edges={len(RELATIONS)} layers={len(layers)} "
          f"canvas={canvas_w}x{canvas_h}px ({canvas_w / 96:.1f}x{canvas_h / 96:.1f} in)")
    print("layer sizes:", [len(l) for l in layers])
    if hits:
        for h in hits[:12]:
            print(f"  ! edge {h[0]}.{h[1]} -> {h[2]} crosses {h[3][:3]}")
        problems.append(f"{len(hits)} edges cross a foreign box")
    if problems:
        print("\n".join("  ! " + p for p in problems[:20] if isinstance(p, str)))
        print("refusing to print:", len(problems), "layout problems")
        return 2
    print("layout OK: no overlap, all boxes inside the canvas, no edge crosses a box")

    body = build(canvas_w, canvas_h, edges, items, slots, layer_top, layer_h, layer_of)
    svg = svg_doc(canvas_w, canvas_h, body)
    html = html_doc(canvas_w, canvas_h, svg)

    html_path = os.path.abspath(args.html)
    os.makedirs(os.path.dirname(html_path), exist_ok=True)
    with open(html_path, "w", encoding="utf-8") as fh:
        fh.write(html)
    print("html:", html_path)

    out = os.path.abspath(args.out)
    if os.path.exists(out):
        os.remove(out)
    chrome = base.find_chrome()
    url = "file:///" + html_path.replace("\\", "/")
    cmd = [chrome, "--headless=new", "--disable-gpu", "--no-sandbox",
           "--no-pdf-header-footer", "--virtual-time-budget=15000",
           f"--print-to-pdf={out}", url]
    print("printing ->", out)
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0 or not os.path.exists(out):
        print(res.stdout[-3000:], res.stderr[-3000:], sep="\n", file=sys.stderr)
        return 1
    print(f"pdf: {out} ({os.path.getsize(out) / 1024:.0f} KB)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
