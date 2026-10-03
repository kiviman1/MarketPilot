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


def development_manifest():
    """Generate an isolated addon from the release source, never a second tree."""
    version, files = manifest()
    result = {}
    for source in files:
        relative = source.relative_to(SOURCE).as_posix()
        if source.suffix not in (".lua", ".toc"):
            result[relative] = source.read_bytes()
            continue
        text = source.read_text(encoding="utf-8")
        text = text.replace("MarketPilotDB", "MarketPilotDevDB")
        text = text.replace("MarketPilotMinimapButton", "MarketPilotDevMinimapButton")
        text = re.sub(r"\bMarketPilot\b", "MarketPilotDev", text)
        text = text.replace("MARKETPILOT", "MARKETPILOTDEV")
        text = re.sub(r"/mp\b", "/mpdev", text)
        # Readable titles differ from identifiers, folders and texture paths.
        text = text.replace('"MarketPilotDev"', '"MarketPilot Dev"') if source.name in ("UI.lua", "Minimap.lua") else text
        text = text.replace("MarketPilotDev settings", "MarketPilot Dev settings")
        text = text.replace("MarketPilotDev:|r", "MarketPilot Dev:|r")
        if source.suffix == ".toc":
            relative = "MarketPilotDev.toc"
            text = text.replace("## Title: MarketPilotDev", "## Title: MarketPilot Dev")
            text = text.replace(f"## Version: {version}", f"## Version: {version}-dev")
        if source.name == "Core.lua":
            text = text.replace(f'local VERSION = "{version}"', f'local VERSION = "{version}-dev"')
        # Fail rather than deploy a partially isolated copy after source changes.
        if re.search(r"MarketPilotDB|MarketPilotMinimapButton|(?<!DEV)MARKETPILOT(?!DEV)|/mp\b|\\MarketPilot\\|\"MarketPilot\"", text):
            raise ValueError(f"Release identity leaked into dev file: {source.name}")
        result[relative] = text.encode("utf-8")
    return result


def write_development(destination):
    destination = Path(destination).resolve()
    if destination.name != "MarketPilotDev" or destination == SOURCE.resolve():
        raise ValueError("Development destination must be a separate MarketPilotDev directory")
    files = development_manifest()
    # Refuse unexpected files instead of deleting anything during synchronization.
    if destination.exists():
        extra = {p.relative_to(destination).as_posix() for p in destination.rglob("*") if p.is_file()} - set(files)
        if extra:
            raise ValueError(f"Unexpected dev files; refusing to overwrite this installation: {sorted(extra)}")
    for name in files:
        if not (destination / name).resolve().is_relative_to(destination):
            raise ValueError("Development file resolves outside its isolated directory")
    for name, content in files.items():
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        # A companion-owned data import is not addon source. Do not replace a
        # successful download with the source tree's empty placeholder.
        if name == "ExternalData.lua" and target.exists():
            continue
        target.write_bytes(content)
    print(f"Development copy: {destination}; /mpdev; isolated MarketPilotDevDB; no release ZIP")


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
    parser.add_argument("--dev-dir", type=Path, help="generate only an isolated MarketPilotDev folder")
    args = parser.parse_args()
    if args.check and args.dev_dir:
        parser.error("--check and --dev-dir are mutually exclusive")
    if args.dev_dir:
        write_development(args.dev_dir)
        return
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
