"""Deterministic development/release identity checks; no deployment or ZIP."""
from pathlib import Path
import tempfile
import unittest
from package import SOURCE, development_manifest, manifest, write_development


class PackagingTests(unittest.TestCase):
    def test_dev_identity(self):
        files = development_manifest()
        toc = files["MarketPilotDev.toc"].decode()
        self.assertNotIn("MarketPilot.toc", files)
        self.assertIn("## Title: MarketPilot Dev", toc)
        self.assertIn("## SavedVariables: MarketPilotDevDB", toc)
        self.assertIn(r"Interface\AddOns\MarketPilotDev\Media\Icon.tga", toc)
        core = files["Core.lua"].decode()
        self.assertIn('itemID == "MarketPilotDev"', core)
        self.assertIn('SLASH_MARKETPILOTDEV1 = "/mpdev"', core)
        self.assertIn("SlashCmdList.MARKETPILOTDEV", core)
        self.assertNotIn("MarketPilotDB", core)
        self.assertIn('local BUTTON_NAME = "MarketPilotDevMinimapButton"', files["Minimap.lua"].decode())
        self.assertIn('"MarketPilot Dev"', files["UI.lua"].decode())

    def test_release_manifest_unchanged(self):
        before = {p: p.read_bytes() for p in manifest()[1]}
        development_manifest()
        self.assertEqual(before, {p: p.read_bytes() for p in manifest()[1]})
        toc = (SOURCE / "MarketPilot.toc").read_text()
        self.assertIn("## Title: MarketPilot\n", toc)
        self.assertIn("## SavedVariables: MarketPilotDB\n", toc)
        self.assertNotIn("Dev", toc)

    def test_only_manifest_files_and_same_asset(self):
        files = development_manifest()
        _, source = manifest()
        self.assertEqual(len(files), len(source))
        self.assertEqual(files["Media/Icon.tga"], (SOURCE / "Media/Icon.tga").read_bytes())
        self.assertFalse(any("WTF" in name or "probe" in name or ".zip" in name for name in files))

    def test_dev_write_preserves_adjacent_public_install(self):
        with tempfile.TemporaryDirectory() as temp:
            parent = Path(temp)
            public = parent / "MarketPilot"
            public.mkdir()
            (public / "owned-by-curseforge").write_bytes(b"preserve")
            write_development(parent / "MarketPilotDev")
            self.assertEqual((public / "owned-by-curseforge").read_bytes(), b"preserve")
            self.assertEqual((parent / "MarketPilotDev/Core.lua").read_bytes(), development_manifest()["Core.lua"])

    def test_refuse_public_or_unknown_directory(self):
        with tempfile.TemporaryDirectory() as temp:
            with self.assertRaises(ValueError):
                write_development(Path(temp) / "MarketPilot")
            dev = Path(temp) / "MarketPilotDev"
            dev.mkdir()
            marker = dev / "unknown.lua"
            marker.write_bytes(b"preserve")
            with self.assertRaises(ValueError):
                write_development(dev)
            self.assertEqual(marker.read_bytes(), b"preserve")
            self.assertEqual(list(dev.iterdir()), [marker])


if __name__ == "__main__":
    unittest.main()
