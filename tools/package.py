"""Build a clean addon ZIP using only the files declared by its TOC."""
from pathlib import Path
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "src/MarketPilot"


def main():
    toc = SOURCE / "MarketPilot.toc"
    text = toc.read_text(encoding="utf-8")
    version = re.search(r"^## Version: ([\d.]+)$", text, re.M).group(1)
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
    output = ROOT / "dist" / f"MarketPilot-{version}.zip"
    output.parent.mkdir(exist_ok=True)
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for source in files:
            archive.write(source, "MarketPilot/" + source.name)
    with zipfile.ZipFile(output) as archive:
        assert archive.testzip() is None
        assert len(archive.namelist()) == len(files)
    print(f"Built {output} ({len(files)} addon files; no WTF/SavedVariables or sale modules)")


if __name__ == "__main__":
    main()
