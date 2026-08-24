#!/usr/bin/env python3
"""Strip eagerly-preloaded families from a built FontManifest.json.

The Flutter engine loads every font listed in FontManifest.json at startup
and blocks the first frame until they all finish downloading. Two groups
must not be in that list:

  * flutter_math_fork's 20 bundled KaTeX TTFs - even when LaTeX rendering is
    disabled in settings. Removing those entries defers loading to the first
    LaTeX render: lib/utils/katex_fonts.dart then registers the same families
    through FontLoader from the still-bundled font assets.

  * Noto Color Emoji (~10MB) - emoji code points are claimed by the leading
    entry of kUnicodeFallbackFontAssets instead, so the coverage probe loads
    it from its still-bundled asset on the first rendered emoji.

Run after `flutter build web` on the built asset bundle. Idempotent.
"""
import json
import pathlib
import sys

FAMILY_PREFIX = "packages/flutter_math_fork/"
DROP_FAMILIES = {"Noto Color Emoji"}


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(f"usage: {sys.argv[0]} <path/to/FontManifest.json>")
    manifest_path = pathlib.Path(sys.argv[1])
    families = json.loads(manifest_path.read_text())
    kept = [
        family
        for family in families
        if not family.get("family", "").startswith(FAMILY_PREFIX)
        and family.get("family") not in DROP_FAMILIES
    ]
    removed = len(families) - len(kept)
    manifest_path.write_text(json.dumps(kept, separators=(",", ":")))
    print(f"strip-katex-manifest: removed {removed} families from {manifest_path}")


if __name__ == "__main__":
    main()
