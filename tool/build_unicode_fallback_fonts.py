#!/usr/bin/env python3
"""Build tree-shaken, lazily-loadable Unicode fallback fonts.

Takes the bundled Unicode Font Set release fonts, removes every glyph that is
already covered by an earlier font in the fallback chain (mirroring the UFS
cmap cleaner), splits each remaining "exclusive" coverage into size-bounded
chunks emitted as separate font families, and generates:

  * assets/font/ufs/*.{otf,ttf}            - the chunked subset fonts
  * lib/config/unicode_fallback_fonts.dart - the ordered family list

Flutter loads asset font families lazily on first use, so chunks that are never
hit are never decoded. WOFF2 is intentionally NOT used: the Flutter engine does
not support it outside the web renderer (flutter/flutter#109108).

Usage: python3 tool/build_unicode_fallback_fonts.py [--src DIR] [--out DIR]
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont

REPO = Path(__file__).resolve().parent.parent

# Fallback chain order MUST match the UFS font-policy.tsv priority.
CHAIN = [
    ("Noto Emoji", "NotoEmoji-Regular.ttf"),
    ("Plangothic P1", "PlangothicP1-Regular.otf"),
    ("Plangothic P2", "PlangothicP2-Regular.otf"),
    ("Source Han Sans SC", "SourceHanSansSC-Regular.otf"),
    ("Noto Unicode", "NotoUnicode.otf"),
    ("Noto Sans Living", "NotoSansLiving-Regular.ttf"),
    ("Noto Sans Historical", "NotoSansHistorical-Regular.ttf"),
    ("Kreative Square", "KreativeSquare.ttf"),
    ("UFSTemp Alpha", "UFSTempAlpha.otf"),
    ("UFSZero Ext", "UFSZeroExt.otf"),
    ("UnicodiaFunky", "UnicodiaFunky.ttf"),
    ("UnicodiaSesh", "UnicodiaSesh.ttf"),
    ("NewGardiner", "NewGardiner.ttf"),
    ("Xdareg(darage)v1(RL)", "UnicodiaDaarage.otf"),
    ("TempSeal", "TempSeal.ttf"),
    # Terminal catch-all: covers everything by design, never subsetted.
    ("Last Resort", "LastResort-Regular.ttf"),
]

KEEP_WHOLE = {"Noto Emoji", "Last Resort"}
SUPERBLOCK_BITS = 13  # 8192 codepoints per superblock
TARGET_CHUNK_BYTES = 512 * 1024
MIN_THRESHOLD = 256
MAX_THRESHOLD = 4096


def sanitize(name: str) -> str:
    return re.sub(r"[^A-Za-z0-9]+", "", name)


def codepoints(font: TTFont) -> set[int]:
    return set(font.getBestCmap().keys())


def make_subset(src_path: Path, unicodes: list[int], out_path: Path) -> None:
    options = subset.Options()
    options.layout_features = ["*"]
    options.notdef_outline = True
    options.glyph_names = False
    options.name_IDs = [0, 1, 2, 3, 4, 6]
    options.ignore_missing_glyphs = True
    options.ignore_missing_unicodes = True
    ss = subset.Subsetter(options=options)
    ss.populate(unicodes=unicodes)
    font = TTFont(str(src_path), lazy=True)
    ss.subset(font)
    font.save(str(out_path))
    font.close()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--src", default=str(REPO / "assets" / "font" / "ufs-src"))
    parser.add_argument("--out", default=str(REPO / "assets" / "font" / "ufs-stage"))
    args = parser.parse_args()
    src_dir, out_dir = Path(args.src), Path(args.out)
    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True)

    covered: set[int] = set()
    families: list[dict] = []  # {family, file} in strict chain order
    stats: list[dict] = []

    for base, filename in CHAIN:
        src_path = src_dir / filename
        orig_size = src_path.stat().st_size
        entry: dict = {"family": base, "orig_size": orig_size}

        probe = TTFont(str(src_path), lazy=True)
        cps = codepoints(probe)
        num_glyphs = probe["maxp"].numGlyphs
        is_cff = "CFF " in probe
        probe.close()
        ext = ".otf" if is_cff else ".ttf"

        if base in KEEP_WHOLE:
            covered |= cps
            shutil.copyfile(src_path, out_dir / filename)
            families.append(
                {"family": base, "file": f"assets/font/ufs/{filename}"}
            )
            entry.update(kind="whole", out_size=orig_size, exclusive=len(cps), chunks=1)
            stats.append(entry)
            print(f"{base}: kept whole ({orig_size >> 10}KB)", flush=True)
            continue

        exclusive = sorted(cps - covered)
        covered |= cps
        entry["exclusive"] = len(exclusive)
        if not exclusive:
            entry.update(kind="dropped", out_size=0, chunks=0)
            stats.append(entry)
            print(f"{base}: fully covered by earlier fonts -> DROPPED", flush=True)
            continue

        avg_glyph = max(orig_size / max(num_glyphs, 1), 1)
        threshold = max(MIN_THRESHOLD, min(MAX_THRESHOLD, int(TARGET_CHUNK_BYTES / avg_glyph)))

        # Group exclusive codepoints into consecutive non-empty superblocks,
        # then split any single superblock that alone busts the budget.
        blocks: list[list[int]] = []
        current_block: int | None = None
        buf: list[int] = []
        for cp in exclusive:
            b = cp >> SUPERBLOCK_BITS
            if b != current_block:
                if buf:
                    blocks.append(buf)
                current_block, buf = b, []
            buf.append(cp)
        if buf:
            blocks.append(buf)

        # Split oversized dense blocks so every chunk stays within budget.
        sized_blocks: list[list[int]] = []
        for block_cps in blocks:
            est = len(block_cps) * avg_glyph
            if est <= TARGET_CHUNK_BYTES * 1.5:
                sized_blocks.append(block_cps)
                continue
            piece = max(1, int(TARGET_CHUNK_BYTES / avg_glyph))
            sized_blocks.extend(
                block_cps[i : i + piece] for i in range(0, len(block_cps), piece)
            )

        # Merge blocks into chunks under the cp-count threshold.
        chunks: list[list[int]] = []
        cur: list[int] = []
        for block_cps in sized_blocks:
            if cur and len(cur) + len(block_cps) > threshold:
                chunks.append(cur)
                cur = []
            cur.extend(block_cps)
        if cur:
            chunks.append(cur)

        stem = sanitize(base)
        total_out = 0
        for chunk_cps in chunks:
            start_cp = chunk_cps[0]
            family_name = f"{base} u{start_cp:05X}"
            file_name = f"{stem}_u{start_cp:05X}{ext}"
            make_subset(src_path, chunk_cps, out_dir / file_name)
            size = (out_dir / file_name).stat().st_size
            total_out += size
            families.append(
                {
                    "family": family_name,
                    "file": f"assets/font/ufs/{file_name}",
                    "first_cp": start_cp,
                    "last_cp": chunk_cps[-1],
                }
            )

        entry.update(kind="split", out_size=total_out, chunks=len(chunks))
        stats.append(entry)
        print(
            f"{base}: {len(exclusive)} exclusive cps -> {len(chunks)} chunks, "
            f"{orig_size >> 10}KB -> {total_out >> 10}KB",
            flush=True,
        )

    dart_lines = [
        "// GENERATED by tool/build_unicode_fallback_fonts.py - do not edit.",
        "// Ordered exactly like the fallback chain: earlier entries win.",
        "// Regenerate with: python3 tool/build_unicode_fallback_fonts.py",
        "const List<String> kUnicodeFallbackFontFamilies = <String>[",
    ]
    dart_lines += [f"  '{f['family']}'," for f in families]
    dart_lines += ["];", ""]
    dart_path = REPO / "lib" / "config" / "unicode_fallback_fonts.dart"
    dart_path.write_text("\n".join(dart_lines) + "\n", encoding="utf-8")

    manifest = {
        "chain": families,
        "stats": stats,
        "total_in": sum(s["orig_size"] for s in stats),
        "total_out": sum(s["out_size"] for s in stats),
    }
    (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=1))

    print(
        f"\nTOTAL: {manifest['total_in'] / 1048576:.1f}MB -> "
        f"{manifest['total_out'] / 1048576:.1f}MB, {len(families)} families",
        flush=True,
    )
    for s in stats:
        if s.get("kind") == "dropped":
            print(f"  dropped (fully covered): {s['family']}")


if __name__ == "__main__":
    main()
