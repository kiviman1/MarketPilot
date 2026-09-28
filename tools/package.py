"""Validate the source manifest; build a ZIP only when explicitly requested.

Use --check for source/CI checks without creating a package or dist directory.
"""
import argparse
from pathlib import Path
import re
import struct
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "src/MarketPilot"


def manifest():
    toc = SOURCE / "MarketPilot.toc"
    text = toc.read_text(encoding="utf-8")
    version = re.search(r"^## Version: ([\d.]+)$", text, re.M).group(1)
    if f'local VERSION = "{version}"' not in (SOURCE / "Core.lua").read_text(encoding="utf-8"):
        raise ValueError("Core and TOC versions must match")
    files = [toc]
    for line in text.splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            source = (SOURCE / line).resolve()
            if source.parent != SOURCE.resolve() or source.suffix != ".lua" or not source.is_file():
                raise ValueError(f"Invalid TOC entry: {line}")
            files.append(source)
    if text.count("## SavedVariables: MarketPilotDB") != 1:
        raise ValueError("Expected exactly one account-wide SavedVariables declaration")
    # The icon is metadata rather than a Lua TOC entry. Include only the known
    # addon-owned asset; never sweep the source/WTF directories into a release.
    icon = SOURCE / "Media/Icon.tga"
    if "## IconTexture: Interface\\AddOns\\MarketPilot\\Media\\Icon.tga" not in text:
        raise ValueError("Expected the addon-owned selection/minimap icon")
    data = icon.read_bytes()
    if len(data) < 18 or data[2] != 2 or data[16] != 32:
        raise ValueError("Icon must be an uncompressed 32-bit TGA")
    width, height = struct.unpack_from("<HH", data, 12)
    if width != 64 or height != 64 or len(data) != 18 + width * height * 4:
        raise ValueError("Expected the complete 64x64 icon")
    files.append(icon)
    return version, files


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="validate only; never create a ZIP")
    args = parser.parse_args()
    version, files = manifest()
    if args.check:
        print(f"Source manifest OK: {version}, {len(files)} files; no build/package produced")
        return
    output = ROOT / "dist" / f"MarketPilot-{version}.zip"
    output.parent.mkdir(exist_ok=True)
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for source in files:
            archive.write(source, "MarketPilot/" + source.relative_to(SOURCE).as_posix())
    with zipfile.ZipFile(output) as archive:
        assert archive.testzip() is None
        assert len(archive.namelist()) == len(files)
    print(f"Built {output} ({len(files)} addon files; no WTF/SavedVariables or sale modules)")


if __name__ == "__main__":
    main()
