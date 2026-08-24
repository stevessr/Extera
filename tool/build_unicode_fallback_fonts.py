#!/usr/bin/env python3
"""Build tree-shaken, on-demand Unicode fallback fonts.

Takes the bundled Unicode Font Set release fonts, removes every glyph that is
already covered by an earlier font in the fallback chain (mirroring the UFS
cmap cleaner), splits each remaining "exclusive" coverage into size-bounded
chunks emitted as separate font families, and generates:

  * assets/font/ufs/*.{otf,ttf}            - the chunked subset fonts
  * lib/config/unicode_fallback_fonts.dart - family and code-point index

The generated fonts are plain Flutter assets, not ``FontManifest`` entries.
At runtime the visible-text scanner probes the current platform font fallback
first, then registers only the chunk that contains a still-missing code point.
WOFF2 is intentionally NOT used: the Flutter engine does not support it outside
the web renderer (flutter/flutter#109108).

Usage: python3 tool/build_unicode_fallback_fonts.py [--src DIR] [--out DIR]
"""

from __future__ import annotations

import argparse
import base64
import json
import re
import shutil
import subprocess
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
    # Last Resort is deliberately omitted. It maps every Unicode scalar to a
    # diagnostic box rather than a real glyph and costs ~9MB, so loading it for
    # an unsupported character would defeat the on-demand fallback policy.
]

# Fonts prepended ahead of CHAIN whose file already ships at a fixed repo
# location. Each tuple is (family, probe path relative to --src, shipped
# asset path). They claim coverage exclusively (later fonts only see the
# remainder) and are never copied into the output directory.
PREPEND_ASSET = [
    (
        # Noto Color Emoji ships as a regular pubspec font asset (the fonts:
        # section must keep bundling it for native platforms). It leads the
        # fallback chain so its coverage claims emoji code points before the
        # monochrome Noto Emoji, but the web build must not preload it: the
        # engine blocks the first frame until every FontManifest font finishes
        # downloading, and this one font is ~10MB. The CI manifest-strip step
        # removes the family from FontManifest.json after `flutter build web`,
        # deferring the download to the first rendered emoji instead.
        "Noto Color Emoji",
        "../NotoColorEmoji.ttf",
        "assets/font/NotoColorEmoji.ttf",
    ),
]

# Emoji shaping relies on GSUB sequences that can cross Unicode blocks. Keep
# this relatively small font whole; every other family is safe to split.
KEEP_WHOLE = {"Noto Emoji"}
SUPERBLOCK_BITS = 13  # 8192 codepoints per superblock
TARGET_CHUNK_BYTES = 512 * 1024
MIN_THRESHOLD = 256
MAX_THRESHOLD = 4096


def sanitize(name: str) -> str:
    return re.sub(r"[^A-Za-z0-9]+", "", name)


def codepoints(font: TTFont) -> set[int]:
    return set(font.getBestCmap().keys())


def contiguous_ranges(cps: list[int]) -> list[tuple[int, int]]:
    """Compress sorted code points into inclusive, contiguous ranges."""
    if not cps:
        return []
    ranges: list[tuple[int, int]] = []
    start = previous = cps[0]
    for cp in cps[1:]:
        if cp != previous + 1:
            ranges.append((start, previous))
            start = cp
        previous = cp
    ranges.append((start, previous))
    return ranges


def append_varint(buffer: bytearray, value: int) -> None:
    """Append an unsigned LEB128 integer."""
    while value >= 0x80:
        buffer.append((value & 0x7F) | 0x80)
        value >>= 7
    buffer.append(value)


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
    parser.add_argument(
        "--metadata-only",
        action="store_true",
        help="reuse already-generated files in --out and rebuild only the Dart index",
    )
    args = parser.parse_args()
    src_dir, out_dir = Path(args.src), Path(args.out)
    if not args.metadata_only:
        if out_dir.exists():
            shutil.rmtree(out_dir)
        out_dir.mkdir(parents=True)

    covered: set[int] = set()
    families: list[dict] = []  # {family, file} in strict chain order
    family_ranges: list[list[tuple[int, int]]] = []
    stats: list[dict] = []

    chain_sources = [
        (base, filename, asset) for base, filename, asset in PREPEND_ASSET
    ] + [(base, filename, None) for base, filename in CHAIN]
    for base, filename, shipped_asset in chain_sources:
        src_path = src_dir / filename
        orig_size = src_path.stat().st_size
        entry: dict = {"family": base, "orig_size": orig_size}

        probe = TTFont(str(src_path), lazy=True)
        cps = codepoints(probe)
        num_glyphs = probe["maxp"].numGlyphs
        is_cff = "CFF " in probe
        probe.close()
        ext = ".otf" if is_cff else ".ttf"

        if shipped_asset is not None:
            # The file already ships at its final location; claim coverage
            # exclusively (like the split path) but never copy or subset it.
            exclusive = sorted(cps - covered)
            covered |= cps
            if not exclusive:
                entry.update(kind="dropped", out_size=0, chunks=0)
                stats.append(entry)
                print(f"{base}: fully covered by earlier fonts -> DROPPED", flush=True)
                continue
            families.append({"family": base, "file": shipped_asset})
            family_ranges.append(contiguous_ranges(exclusive))
            entry.update(kind="whole", out_size=orig_size, exclusive=len(exclusive), chunks=1)
            stats.append(entry)
            print(f"{base}: kept whole at {shipped_asset} ({orig_size >> 10}KB)", flush=True)
            continue
        if base in KEEP_WHOLE:
            # Keep the file intact (GSUB sequences may cross blocks) but only
            # claim code points not already covered by an earlier font, so
            # generated ranges stay disjoint.
            exclusive_cps = sorted(cps - covered)
            covered |= cps
            if not exclusive_cps:
                entry.update(kind="dropped", out_size=0, chunks=0)
                stats.append(entry)
                print(f"{base}: fully covered by earlier fonts -> DROPPED", flush=True)
                continue
            if not args.metadata_only:
                shutil.copyfile(src_path, out_dir / filename)
            families.append(
                {"family": base, "file": f"assets/font/ufs/{filename}"}
            )
            family_ranges.append(contiguous_ranges(exclusive_cps))
            entry.update(kind="whole", out_size=orig_size, exclusive=len(exclusive_cps), chunks=1)
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
            if not args.metadata_only:
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
            family_ranges.append(contiguous_ranges(chunk_cps))

        entry.update(kind="split", out_size=total_out, chunks=len(chunks))
        stats.append(entry)
        print(
            f"{base}: {len(exclusive)} exclusive cps -> {len(chunks)} chunks, "
            f"{orig_size >> 10}KB -> {total_out >> 10}KB",
            flush=True,
        )

    # The tree-shaken families have disjoint cmaps. Flatten their coverage into
    # a globally sorted range table so Dart can find an asset with one binary
    # search without opening or downloading any font file.
    indexed_ranges = sorted(
        (start, end, family_index)
        for family_index, ranges in enumerate(family_ranges)
        for start, end in ranges
    )
    for previous, current in zip(indexed_ranges, indexed_ranges[1:]):
        if current[0] <= previous[1]:
            raise RuntimeError(
                "generated fallback cmaps overlap: "
                f"U+{previous[0]:04X}-U+{previous[1]:04X} and "
                f"U+{current[0]:04X}-U+{current[1]:04X}"
            )

    packed_ranges = bytearray()
    previous_end = -1
    for start, end, family_index in indexed_ranges:
        append_varint(packed_ranges, start - previous_end - 1)
        append_varint(packed_ranges, end - start)
        append_varint(packed_ranges, family_index)
        previous_end = end
    encoded_ranges = base64.b64encode(packed_ranges).decode("ascii")

    dart_lines = [
        "// GENERATED by tool/build_unicode_fallback_fonts.py - do not edit.",
        "// Ordered exactly like the fallback chain: earlier entries win.",
        "// Regenerate with: python3 tool/build_unicode_fallback_fonts.py",
        "// Families are NOT declared in pubspec.yaml: the web/wasm engine preloads",
        "// every FontManifest entry at startup. Runtime code probes system",
        "// fallback coverage, then loads only the matching plain asset.",
        "class UnicodeFallbackFontAsset {",
        "  const UnicodeFallbackFontAsset(this.family, this.asset);",
        "",
        "  final String family;",
        "  final String asset;",
        "}",
        "",
        "const List<UnicodeFallbackFontAsset> kUnicodeFallbackFontAssets =",
        "    <UnicodeFallbackFontAsset>[",
    ]
    dart_lines += [
        f"  UnicodeFallbackFontAsset('{f['family']}', '{f['file']}'),"
        for f in families
    ]
    dart_lines += [
        "];",
        "",
        "// Delta/length/asset-index triples encoded as unsigned LEB128, then",
        "// base64. Decoded lazily on the first non-ASCII text scan.",
        "const String kUnicodeFallbackFontRangeIndexBase64 =",
    ]
    dart_lines += [
        f"  '{encoded_ranges[offset : offset + 80]}'"
        for offset in range(0, len(encoded_ranges), 80)
    ]
    dart_lines += [";", ""]
    dart_path = REPO / "lib" / "config" / "unicode_fallback_fonts.dart"
    dart_path.write_text("\n".join(dart_lines) + "\n", encoding="utf-8")
    subprocess.run(["dart", "format", str(dart_path)], check=True)

    manifest = {
        "chain": families,
        "stats": stats,
        "total_in": sum(s["orig_size"] for s in stats),
        "total_out": sum(s["out_size"] for s in stats),
    }
    if not args.metadata_only:
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
