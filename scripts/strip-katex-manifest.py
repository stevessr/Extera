#!/usr/bin/env python3
"""Strip lazily-loaded package fonts from a built FontManifest.json.

The Flutter engine loads every font listed in FontManifest.json at startup:

- flutter_math_fork's 20 KaTeX TTFs are fetched and decoded even when LaTeX
  rendering is disabled in settings. lib/utils/katex_fonts.dart registers the
  same families on demand at the first LaTeX render.
- pro_image_editor's icon TTF is fetched even though the editor's Dart code
  is deferred (image_editor_dialog.dart); that dialog registers the family
  before opening the editor.

Removing those manifest entries defers loading to first use; the font assets
themselves stay bundled. Run after `flutter build web` on the built asset
bundle. Idempotent.
"""
import json
import pathlib
import sys

FAMILY_PREFIXES = (
    "packages/flutter_math_fork/",
    "packages/pro_image_editor/",
)


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(f"usage: {sys.argv[0]} <path/to/FontManifest.json>")
    manifest_path = pathlib.Path(sys.argv[1])
    families = json.loads(manifest_path.read_text())
    kept = [
        family
        for family in families
        if not family.get("family", "").startswith(FAMILY_PREFIXES)
    ]
    removed = len(families) - len(kept)
    manifest_path.write_text(json.dumps(kept, separators=(",", ":")))
    print(f"strip-katex-manifest: removed {removed} families from {manifest_path}")


if __name__ == "__main__":
    main()
