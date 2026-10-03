"""Offline companion behavior; Tk smoke tests create only their own hidden window."""
from pathlib import Path
import tempfile
import threading
import tkinter as tk
import unittest
from unittest.mock import patch

from sync.app import App, Jobs


class JobsTests(unittest.TestCase):
    def test_single_job_and_queued_progress(self):
        jobs = Jobs()
        release = threading.Event()
        def action():
            jobs.progress(1, 2, "item 2770")
            self.assertTrue(release.wait(2))
            return "result"
        self.assertTrue(jobs.start(action))
        self.assertFalse(jobs.start(lambda: self.fail("parallel job")))
        self.assertTrue(jobs.busy)
        release.set()
        jobs.worker.join(2)
        self.assertEqual(jobs.drain(), [("progress", (1, 2, "item 2770")), ("success", "result"), ("finished", None)])
        self.assertFalse(jobs.busy)
        self.assertTrue(jobs.start(lambda: "next"))
        jobs.worker.join(2)
        self.assertEqual(jobs.drain()[-1][0], "finished")

    def test_failure_releases_operation_without_retry(self):
        jobs, calls = Jobs(), []
        def action():
            calls.append(1)
            raise ValueError("offline")
        jobs.start(action)
        jobs.worker.join(2)
        self.assertEqual(jobs.drain(), [("error", "offline"), ("finished", None)])
        self.assertEqual(calls, [1])
        self.assertFalse(jobs.busy)


class AppTests(unittest.TestCase):
    def setUp(self):
        try:
            self.root = tk.Tk()
            self.root.withdraw()
        except tk.TclError as error:
            self.skipTest(f"Tk display unavailable: {error}")
        self.addCleanup(self.root.destroy)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.destination = Path(self.temp.name) / "MarketPilotDev"
        self.destination.mkdir()
        (self.destination / "MarketPilotDev.toc").write_text("ExternalData.lua\nExternalMarket.lua\n")
        (self.destination / "ExternalMarket.lua").write_text("-- fixture")
        (self.destination / "Items.lua").write_bytes(Path("src/MarketPilot/Items.lua").read_bytes())
        self.calls = []
        calls = self.calls
        class FakeClient:
            def markets(self):
                return [{"id": "forever.normal.horde.us", "label": "Normal Horde", "region": "us",
                         "game": "forever", "ruleset": "normal", "faction": "horde"}]
            def update(self, market, ids, progress):
                calls.append((market, ids))
                progress(2, 2, "fixture")
                return {"schema": 1, "source": "AHledger", "url": "https://ahledger.com",
                        "market": market["id"], "marketLabel": market["label"], "region": "us",
                        "fetchedAt": 1791064006, "itemIDs": [2770], "items": {
                            2770: {"latest": {"t": 1791064006, "median": 200}, "hourly": [], "daily": []}}}
        self.app = App(self.root, FakeClient())
        self.app.jobs.worker.join(2)
        self.app.receive()

    def test_market_must_be_chosen_no_automatic_realm_mapping(self):
        self.assertEqual(self.app.selection.get(), "")
        self.assertEqual(str(self.app.update_button["state"]), "disabled")
        self.app.update()
        self.assertEqual(self.calls, [])
        self.assertIn("forever.normal.horde.us", self.app.market_labels[0])

    def test_manual_update_writes_only_data_and_gives_reload_instructions(self):
        self.app.selection.set(self.app.market_labels[0])
        self.app.target.set(str(self.destination))
        self.app.controls()
        self.app.update()
        self.assertEqual(str(self.app.update_button["state"]), "disabled")
        self.app.update()
        self.app.jobs.worker.join(2)
        self.app.receive()
        self.assertEqual(len(self.calls), 1)
        self.assertEqual(len(self.calls[0][1]), 56)
        self.assertIn("Güncellendi", self.app.status.get())
        self.assertIn("/reload", self.app.message.get())
        self.assertEqual(str(self.app.update_button["state"]), "normal")
        self.assertIn("MP.ExternalPayload", (self.destination / "ExternalData.lua").read_text())
        self.assertEqual(sorted(p.name for p in self.destination.iterdir()),
                         ["ExternalData.lua", "ExternalMarket.lua", "Items.lua", "MarketPilotDev.toc"])

    def test_uses_selected_installed_catalogue_instead_of_checkout_ids(self):
        (self.destination / "Items.lua").write_text("local Items={ itemIDs={2770} }")
        self.app.selection.set(self.app.market_labels[0])
        self.app.target.set(str(self.destination))
        self.app.update()
        self.app.jobs.worker.join(2)
        self.app.receive()
        self.assertEqual(self.calls[0][1], [2770])
        self.assertIn("1/1", self.app.status.get())

    def test_incompatible_install_does_not_start_http_update(self):
        self.app.selection.set(self.app.market_labels[0])
        self.app.target.set(str(Path(self.temp.name) / "MarketPilot"))
        self.app.update()
        self.assertEqual(self.calls, [])
        self.assertIn("başlamadı", self.app.status.get())

    def test_network_failure_keeps_data_and_returns_controls(self):
        data = self.destination / "ExternalData.lua"
        data.write_bytes(b"last successful data")
        self.app.selection.set(self.app.market_labels[0])
        self.app.target.set(str(self.destination))
        with patch.object(self.app.client, "update", side_effect=ValueError("offline")) as update:
            self.app.update()
            self.app.jobs.worker.join(2)
            self.app.receive()
        self.assertEqual(update.call_count, 1)
        self.assertEqual(data.read_bytes(), b"last successful data")
        self.assertIn("başarısız", self.app.status.get())
        self.assertEqual(str(self.app.update_button["state"]), "normal")


if __name__ == "__main__":
    unittest.main()
