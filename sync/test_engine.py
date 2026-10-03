"""Deterministic standard-library tests; no live AHledger requests or addon writes."""

from copy import deepcopy
from datetime import datetime, timezone
from email.message import Message
from email.utils import format_datetime
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit

from sync.engine import (API_BASE, MAX_BODY_BYTES, MAX_NUMBER, Client, CooldownError,
                         SyncError, load_catalog, serialize_payload, validate_destination,
                         write_payload)


NOW = 1_791_072_000
MARKET = {"id": "forever.pvp.alliance.eu", "game": "forever", "ruleset": "pvp",
          "faction": "alliance", "region": "eu", "label": "Forever Alliance"}
TIMESTAMP = "2026-10-03T12:00:00Z"
EARLIER = "2026-10-03T11:00:00+00:00"
EPOCH = int(datetime.fromisoformat(TIMESTAMP.replace("Z", "+00:00")).timestamp())


def response_data(item_id=2770, range_name="7d"):
    return {"market": MARKET["id"], "item": {"id": item_id, "name": "Copper Ore"},
            "latest": {"observedAt": TIMESTAMP, "minBuyout": 100, "median": 125.5,
                       "quantity": 50, "auctions": 8, "median7d": 120, "median30d": None},
            "range": range_name,
            "series": [{"t": TIMESTAMP, "min": 100, "median": 125.5, "p25": 110,
                        "p75": 150, "quantity": 50, "auctions": 8, "cleanMedian": 999},
                       {"t": EARLIER, "min": None, "median": None,
                        "p25": None, "p75": None, "quantity": 0, "auctions": 0}],
            "ignored": "not exported"}


def fixture_payload():
    opener = FakeOpener()
    return Client(opener=opener, clock=lambda: NOW).update(MARKET, [2770])


class FakeResponse:
    def __init__(self, data, headers=None, status=200, raw=None):
        self.body = io.BytesIO(raw if raw is not None else json.dumps(data).encode("utf-8"))
        self.status = status
        self.headers = headers if headers is not None else {"Cache-Control": "max-age=300"}
        self.closed = False
        self.read_sizes = []

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.closed = True

    def read(self, size):
        self.read_sizes.append(size)
        return self.body.read(size)


class FakeOpener:
    def __init__(self, overrides=None):
        self.overrides = overrides or {}
        self.calls = []
        self.responses = []

    def __call__(self, request, timeout):
        self.calls.append((request, timeout))
        parsed = urlsplit(request.full_url)
        key = parsed.path + ("?" + parsed.query if parsed.query else "")
        entry = self.overrides.get(key)
        if isinstance(entry, BaseException):
            raise entry
        if callable(entry):
            response = entry()
        elif isinstance(entry, FakeResponse):
            response = entry
        elif entry is not None:
            response = FakeResponse(entry)
        elif parsed.path == "/v1/markets":
            response = FakeResponse({"markets": [MARKET, {**MARKET, "id": "classic-eu", "game": "classic"}]})
        else:
            item_id = int(parsed.path.rsplit("/", 1)[1])
            response = FakeResponse(response_data(item_id, parsed.query.split("=", 1)[1]))
        self.responses.append(response)
        return response


class NetworkTests(unittest.TestCase):
    def test_markets_filtered_and_bounded_get_headers(self):
        opener = FakeOpener()
        markets = Client(opener, clock=lambda: NOW).markets()
        self.assertEqual(markets, [MARKET])
        request, timeout = opener.calls[0]
        self.assertEqual(request.full_url, API_BASE + "/v1/markets")
        self.assertEqual(request.get_method(), "GET")
        self.assertEqual(request.get_header("User-agent"), "MarketPilotSync/0.1")
        self.assertEqual(timeout, 20)
        self.assertEqual(opener.responses[0].read_sizes, [MAX_BODY_BYTES + 1])
        self.assertTrue(opener.responses[0].closed)

    def test_update_maps_whitelist_and_progress_sequentially(self):
        opener, progress = FakeOpener(), []
        payload = Client(opener, clock=lambda: NOW).update(MARKET, [2771, 2770, 2770], lambda *args: progress.append(args))
        self.assertEqual(payload["itemIDs"], [2770, 2771])
        self.assertEqual([urlsplit(req.full_url).path.rsplit("/", 1)[1] for req, _ in opener.calls], ["2770", "2770", "2771", "2771"])
        self.assertEqual([entry[0] for entry in progress], [0, 1, 2, 3, 4])
        self.assertTrue(all(entry[1] == 4 for entry in progress))
        item = payload["items"][2770]
        self.assertEqual(item["latest"], {"t": EPOCH, "lowest": 100, "median": 125.5,
                                         "quantity": 50, "auctions": 8, "median7d": 120})
        self.assertEqual(item["hourly"][0], {"t": EPOCH - 3600, "quantity": 0, "auctions": 0})
        self.assertEqual(item["hourly"][1]["median"], 125.5)
        self.assertEqual(item["hourly"][1]["min"], 100)
        self.assertNotIn("cleanMedian", item["hourly"][1])
        self.assertNotIn("median30d", item["latest"])
        self.assertEqual(payload["fetchedAt"], NOW)

    def test_null_latest_and_empty_series_remain_unknown(self):
        overrides = {}
        for range_name in ("7d", "30d"):
            data = response_data(range_name=range_name)
            data.update(latest=None, series=[])
            overrides[f"/v1/prices/{MARKET['id']}/2770?range={range_name}"] = data
        payload = Client(FakeOpener(overrides), clock=lambda: NOW).update(MARKET, [2770])
        self.assertEqual(payload["items"][2770], {"hourly": [], "daily": []})
        self.assertIn('["hourly"] = {}', serialize_payload(payload))
        self.assertNotIn('["latest"]', serialize_payload(payload))

    def test_newest_latest_stays_a_single_observation(self):
        daily = response_data(range_name="30d")
        daily["latest"] = {"observedAt": "2026-10-03T13:00:00Z", "median": None, "quantity": 3}
        client = Client(FakeOpener({f"/v1/prices/{MARKET['id']}/2770?range=30d": daily}), clock=lambda: NOW)
        self.assertEqual(client.update(MARKET, [2770])["items"][2770]["latest"], {"t": EPOCH + 3600, "quantity": 3})

    def test_cache_max_age_age_expiry_and_no_store(self):
        clock = [NOW]
        opener = FakeOpener({"/v1/markets": lambda: FakeResponse({"markets": [MARKET]}, {"Cache-Control": 'public, max-age="60"', "Age": "10"})})
        client = Client(opener, clock=lambda: clock[0])
        client.markets()
        clock[0] += 49
        client.markets()
        self.assertEqual(len(opener.calls), 1)
        clock[0] += 1
        client.markets()
        self.assertEqual(len(opener.calls), 2)
        for directive in ("max-age=300, no-store", "no-cache, max-age=300", "max-age=0"):
            uncached = FakeOpener({"/v1/markets": lambda: FakeResponse({"markets": [MARKET]}, {"Cache-Control": directive})})
            client = Client(uncached, clock=lambda: NOW)
            client.markets()
            client.markets()
            self.assertEqual(len(uncached.calls), 2)

    def test_retry_after_and_cooldown_never_retry_automatically(self):
        for status, header, expected in ((429, "120", 120),
                                         (503, format_datetime(datetime.fromtimestamp(NOW + 90, timezone.utc), usegmt=True), 90),
                                         (429, "invalid", 60)):
            with self.subTest(status=status, header=header):
                response = FakeResponse({}, {"Retry-After": header}, status)
                opener = FakeOpener({"/v1/markets": response})
                client = Client(opener, clock=lambda: NOW)
                with self.assertRaises(CooldownError) as first:
                    client.markets()
                self.assertEqual(first.exception.retry_after, expected)
                self.assertEqual(first.exception.retry_at, NOW + expected)
                with self.assertRaises(CooldownError):
                    client.markets()
                self.assertEqual(len(opener.calls), 1)
                self.assertTrue(response.closed)

    def test_http_error_response_uses_retry_after_and_closes(self):
        headers = Message()
        headers["Retry-After"] = "45"
        stream = io.BytesIO(b"failure")
        error = HTTPError(API_BASE + "/v1/markets", 429, "limit", headers, stream)
        client = Client(FakeOpener({"/v1/markets": error}), clock=lambda: NOW)
        with self.assertRaises(CooldownError) as caught:
            client.markets()
        self.assertEqual(caught.exception.retry_after, 45)
        self.assertTrue(stream.closed)

    def test_local_rate_limit_and_expiry(self):
        clock = [NOW]
        opener = FakeOpener({"/v1/markets": lambda: FakeResponse({"markets": [MARKET]}, {})})
        client = Client(opener, clock=lambda: clock[0])
        for _ in range(300):
            client.markets()
        with self.assertRaises(CooldownError) as caught:
            client.markets()
        self.assertEqual(caught.exception.retry_after, 60)
        self.assertEqual(len(opener.calls), 300)
        clock[0] += 60
        client.markets()
        self.assertEqual(len(opener.calls), 301)

    def test_errors_bounds_and_corrupt_json(self):
        cases = [URLError("offline"), TimeoutError(),
                 FakeResponse({}, status=500),
                 FakeResponse({}, raw=b'{"markets": [], "markets": []}'),
                 FakeResponse({}, raw=b'{"markets": NaN}'),
                 FakeResponse({}, raw=b"\xff"),
                 FakeResponse({}, raw=b"{"),
                 FakeResponse({}, raw=b" " * (MAX_BODY_BYTES + 1)),
                 FakeResponse({}, {"Content-Length": str(MAX_BODY_BYTES + 1)}),
                 FakeResponse({}, {"Content-Length": "unknown"})]
        for entry in cases:
            with self.subTest(entry=entry):
                opener = FakeOpener({"/v1/markets": entry})
                with self.assertRaises(SyncError):
                    Client(opener, clock=lambda: NOW).markets()
                self.assertEqual(len(opener.calls), 1)

    def test_market_validation_before_any_request(self):
        for market in ({**MARKET, "game": "classic"}, {**MARKET, "id": ""}, {**MARKET, "region": None},
                       {**MARKET, "id": "forever.pvp.alliance.us"},
                       {**MARKET, "id": "forever.pvp.alliance.eu/elsewhere"},
                       {**MARKET, "id": "forever.PVP.alliance.eu"},
                       {**MARKET, "label": "|cffff0000unsafe|r"},
                       {**MARKET, "label": "é" * 65}, {**MARKET, "label": "  "}):
            opener = FakeOpener()
            with self.assertRaises(SyncError):
                Client(opener, clock=lambda: NOW).update(market, [2770])
            self.assertEqual(opener.calls, [])


class DataValidationTests(unittest.TestCase):
    def assert_bad_response(self, mutate):
        data = response_data()
        mutate(data)
        opener = FakeOpener({f"/v1/prices/{MARKET['id']}/2770?range=7d": data})
        with self.assertRaises(SyncError):
            Client(opener, clock=lambda: NOW).update(MARKET, [2770])
        self.assertEqual(len(opener.calls), 1)

    def test_market_item_and_range_mismatches(self):
        for mutate in (lambda d: d.update(market="other-market"),
                       lambda d: d["item"].update(id=2771),
                       lambda d: d["item"].update(id=True),
                       lambda d: d.update(range="30d"),
                       lambda d: d.pop("latest"),
                       lambda d: d.update(series=None)):
            with self.subTest(mutate=mutate):
                self.assert_bad_response(mutate)

    def test_prices_positive_finite_and_bounded(self):
        for value in (0, -1, True, "12", float("inf"), float("nan"), MAX_NUMBER + 1, 10 ** 1000):
            with self.subTest(value=str(value)[:30]):
                self.assert_bad_response(lambda d: d["latest"].update(median=value))
                self.assert_bad_response(lambda d: d["series"][0].update(min=value))
        data = response_data()
        data["latest"].update(median=MAX_NUMBER, median30d=0.25)
        client = Client(FakeOpener({f"/v1/prices/{MARKET['id']}/2770?range=7d": data}), clock=lambda: NOW)
        latest = client.update(MARKET, [2770])["items"][2770]["latest"]
        self.assertEqual(latest["median"], MAX_NUMBER)
        self.assertEqual(latest["median30d"], 0.25)

    def test_counts_are_bounded_integers(self):
        for value in (-1, True, 1.0, 2.5, "5", MAX_NUMBER + 1):
            with self.subTest(value=value):
                self.assert_bad_response(lambda d: d["latest"].update(quantity=value))
                self.assert_bad_response(lambda d: d["series"][0].update(auctions=value))

    def test_contradictions_rejected_only_for_known_same_observation_fields(self):
        self.assert_bad_response(lambda d: d["latest"].update(minBuyout=126))
        for fields in ({"min": 126}, {"p25": 126}, {"p75": 125},
                       {"median": None, "p25": 160, "p75": 150},
                       {"median": None, "min": 120, "p25": 110},
                       {"median": None, "p25": None, "min": 151, "p75": 150}):
            with self.subTest(fields=fields):
                self.assert_bad_response(lambda d: d["series"][0].update(fields))
        data = response_data()
        data["latest"].update(minBuyout=500, median=None, median7d=100)
        data["series"][0].update(min=None, median=1000, p25=None, p75=None)
        client = Client(FakeOpener({f"/v1/prices/{MARKET['id']}/2770?range=7d": data}), clock=lambda: NOW)
        self.assertEqual(client.update(MARKET, [2770])["items"][2770]["latest"]["lowest"], 500)

    def test_timezone_dates_duplicates_and_series_limits(self):
        for value in ("2026-10-03T12:00:00", "2026-99-03T12:00:00Z", "not a date", None):
            with self.subTest(timestamp=value):
                self.assert_bad_response(lambda d: d["latest"].update(observedAt=value))
        self.assert_bad_response(lambda d: d["series"][1].update(t=TIMESTAMP))
        self.assert_bad_response(lambda d: d.update(series=[d["series"][0]] * 201))
        daily = response_data(range_name="30d")
        daily["series"] *= 21
        opener = FakeOpener({f"/v1/prices/{MARKET['id']}/2770?range=30d": daily})
        with self.assertRaises(SyncError):
            Client(opener, clock=lambda: NOW).update(MARKET, [2770])
        self.assertEqual(len(opener.calls), 2)

    def test_payload_revalidation_rejects_bad_fields(self):
        for mutate in (lambda p: p.update(schema=1.0),
                       lambda p: p.update(source="another source"),
                       lambda p: p.update(url="https://elsewhere.example"),
                       lambda p: p.update(itemIDs=[2770, 2770]),
                       lambda p: p["items"].update({2771: {"hourly": [], "daily": []}}),
                       lambda p: p["items"][2770]["latest"].update(median=-1),
                       lambda p: p.update(marketLabel="bad\nlabel"),
                       lambda p: p.update(marketLabel="\ud800")):
            payload = fixture_payload()
            mutate(payload)
            with self.subTest(mutate=mutate), self.assertRaises(SyncError):
                serialize_payload(payload)

    def test_serializer_drops_unknown_data_and_escapes_strings(self):
        payload = fixture_payload()
        payload["attack"] = "os.execute('unexpected')"
        payload["items"][2770]["attack"] = "assert(false)"
        payload["marketLabel"] = 'é"}; os.execute("unexpected"); --\\name'
        source = serialize_payload(payload)
        self.assertNotIn('["attack"]', source)
        self.assertIn('é\\"}; os.execute(\\"unexpected\\"); --\\\\name', source)
        self.assertTrue(source.endswith("}\n"))
        self.assertEqual(source.count("MP.ExternalPayload ="), 1)

    def test_literal_lua_loads_without_executing_label_content(self):
        try:
            from lupa.lua51 import LuaRuntime
        except ImportError:
            self.skipTest("Optional existing Lua 5.1 test runtime is unavailable.")
        runtime = LuaRuntime()
        payload = fixture_payload()
        payload["marketLabel"] = 'é"}; injected = true; --\\123'
        source = serialize_payload(payload)
        loader = runtime.eval("function(source) local chunk, err = loadstring(source); assert(chunk, err); local mp = {}; chunk('MarketPilotDev', mp); return mp.ExternalPayload end")
        loaded = loader(source)
        self.assertEqual(loaded["marketLabel"], payload["marketLabel"])
        self.assertEqual(loaded["items"][2770]["latest"]["median"], 125.5)
        self.assertEqual(loaded["items"][2770]["hourly"][1]["quantity"], 0)
        self.assertIsNone(runtime.globals().injected)

    def test_market_token_boundaries_match_consumer_contract(self):
        payload = fixture_payload()
        payload.update(market="forever.future_ruleset.faction-2.eu_2", region="eu_2")
        self.assertIn('"forever.future_ruleset.faction-2.eu_2"', serialize_payload(payload))
        for market in ("forever.-normal.horde.us", "forever.normal.-horde.us",
                       "forever.normal.horde.-us", "forever._normal.horde.us",
                       "forever.normal._horde.us", "forever.normal.horde._us"):
            with self.subTest(market=market), self.assertRaises(SyncError):
                serialize_payload({**payload, "market": market, "region": market.rsplit(".", 1)[1]})
        with self.assertRaises(SyncError):
            serialize_payload({**payload, "region": "us"})

    def test_exported_markets_and_unicode_load_through_lua_consumer(self):
        try:
            from lupa.lua51 import LuaRuntime
        except ImportError:
            self.skipTest("Optional existing Lua 5.1 test runtime is unavailable.")
        runtime = LuaRuntime()
        consumer = (Path(__file__).resolve().parents[1] / "src/MarketPilot/ExternalMarket.lua").read_text(encoding="utf-8")
        consume = runtime.eval("""function(consumer, source, market, region)
            local mp = {}
            assert(loadstring(source))('MarketPilotDev', mp)
            assert(loadstring(consumer))('MarketPilotDev', mp)
            if market then mp.ExternalPayload.market = market end
            if region then mp.ExternalPayload.region = region end
            return mp.ExternalMarket.New(mp.ExternalPayload, {2770})
        end""")
        markets = [f"forever.{ruleset}.{faction}.us"
                   for ruleset in ("normal", "pvp", "rp") for faction in ("horde", "alliance")]
        markets.append("forever.future_ruleset.faction-2.eu_2")
        for market in markets:
            payload = fixture_payload()
            label = "Normal – Horde / Royaume français"
            payload.update(market=market, region=market.rsplit(".", 1)[1], marketLabel=label)
            with self.subTest(market=market):
                loaded = consume(consumer, serialize_payload(payload), None, None)
                self.assertEqual(loaded["status"], "OK")
                self.assertEqual(loaded["market"], market)
                self.assertEqual(loaded["marketLabel"], label)
        source = serialize_payload(fixture_payload())
        for market, region in (("forever.-normal.horde.us", "us"),
                               ("forever.normal.-horde.us", "us"),
                               ("forever.normal.horde._us", "_us"),
                               ("forever.normal.horde.us", "eu")):
            with self.subTest(market=market, region=region):
                self.assertEqual(consume(consumer, source, market, region)["status"], "INVALID")


class CatalogTests(unittest.TestCase):
    def test_reads_actual_source_catalogue_without_duplicate_list(self):
        ids = load_catalog(Path(__file__).resolve().parents[1] / "src/MarketPilot/Items.lua")
        self.assertEqual(len(ids), 56)
        self.assertEqual(len(ids), len(set(ids)))
        self.assertIn(2770, ids)

    def test_comments_quoted_examples_and_duplicate_ids(self):
        with tempfile.TemporaryDirectory() as temp:
            file = Path(temp) / "Items.lua"
            file.write_text('local text = "itemIDs = {999}"\n-- itemIDs = {111}\nlocal a = { itemIDs = {2770, 2771, 2770} }', encoding="utf-8")
            self.assertEqual(load_catalog(file), [2770, 2771])

    def test_rejects_expressions_malformed_and_unbounded_catalogue(self):
        with tempfile.TemporaryDirectory() as temp:
            file = Path(temp) / "Items.lua"
            for source in ("itemIDs = {2770, 1+2}", "itemIDs = other", "itemIDs = {true}",
                           "--[[ itemIDs = {2770} ]]", '"itemIDs = {2770}',
                           "itemIDs = {0}", "itemIDs = {" + ",".join(str(i) for i in range(1, 202)) + "}"):
                file.write_text(source, encoding="utf-8")
                with self.subTest(source=source[:30]), self.assertRaises(SyncError):
                    load_catalog(file)


class DestinationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.folder = Path(self.temporary.name) / "MarketPilotDev"
        self.folder.mkdir()
        (self.folder / "MarketPilotDev.toc").write_text("## Title: MarketPilot Dev\nExternalData.lua\nExternalMarket.lua\n", encoding="utf-8")
        (self.folder / "ExternalMarket.lua").write_text("-- consumer\n", encoding="utf-8")
        (self.folder / "Items.lua").write_text("local Items = { categories = { { itemIDs = {2770, 2447} } } }\n", encoding="utf-8")
        (self.folder / "ExternalData.lua").write_text("-- previous data\n", encoding="utf-8")

    def assert_preserved(self):
        self.assertEqual((self.folder / "ExternalData.lua").read_text(encoding="utf-8"), "-- previous data\n")
        self.assertFalse(list(self.folder.glob(".ExternalData-*.tmp")))

    def test_atomic_write_changes_only_external_data(self):
        before = {path.name: path.read_bytes() for path in self.folder.iterdir()}
        payload = fixture_payload()
        result = write_payload(self.folder, payload)
        self.assertEqual(result, self.folder / "ExternalData.lua")
        self.assertEqual(result.read_text(encoding="utf-8"), serialize_payload(payload))
        after = {path.name: path.read_bytes() for path in self.folder.iterdir()}
        self.assertEqual(set(after), set(before))
        for name in before.keys() - {"ExternalData.lua"}:
            self.assertEqual(after[name], before[name])

    def test_invalid_data_and_failed_replace_preserve_previous_file(self):
        payload = fixture_payload()
        invalid = deepcopy(payload)
        invalid["items"][2770]["latest"]["median"] = 0
        with self.assertRaises(SyncError):
            write_payload(self.folder, invalid)
        self.assert_preserved()
        with patch("sync.engine.os.replace", side_effect=PermissionError("locked")):
            with self.assertRaisesRegex(SyncError, "previous file was preserved"):
                write_payload(self.folder, payload)
        self.assert_preserved()

    def test_failed_network_batch_preserves_previous_file(self):
        bad = response_data(range_name="30d")
        bad["latest"]["median"] = -1
        client = Client(FakeOpener({f"/v1/prices/{MARKET['id']}/2770?range=30d": bad}), clock=lambda: NOW)
        with self.assertRaises(SyncError):
            write_payload(self.folder, client.update(MARKET, [2770]))
        self.assert_preserved()

    def test_requires_existing_supported_folder_and_toc(self):
        for destination in (self.folder.parent, self.folder.parent / "WTF", self.folder.parent / "MarketPilot"):
            with self.subTest(destination=destination), self.assertRaises(SyncError):
                validate_destination(destination)
        toc = self.folder / "MarketPilotDev.toc"
        for text in ("ExternalMarket.lua\n", "ExternalMarket.lua\nExternalData.lua\n",
                     "# ExternalData.lua\nExternalMarket.lua\n", "ExternalData.lua\nExternalData.lua\nExternalMarket.lua\n"):
            toc.write_text(text, encoding="utf-8")
            with self.subTest(text=text), self.assertRaises(SyncError):
                write_payload(self.folder, fixture_payload())
            self.assert_preserved()

    def test_linked_output_is_rejected_without_replacing_existing_data(self):
        original = Path.is_symlink
        output = self.folder / "ExternalData.lua"
        with patch.object(Path, "is_symlink", lambda path: path == output or original(path)):
            with self.assertRaises(SyncError):
                write_payload(self.folder, fixture_payload())
        self.assert_preserved()

    def test_export_must_fit_destination_catalogue_and_preserve_previous_file(self):
        payload = fixture_payload()
        # A subset of the destination catalogue is valid; a narrower old
        # installation cannot accept an item unknown to its own consumer.
        self.assertEqual(payload["itemIDs"], [2770])
        (self.folder / "Items.lua").write_text("local Items = { itemIDs = {2447} }", encoding="utf-8")
        with self.assertRaisesRegex(SyncError, "not configured"):
            write_payload(self.folder, payload)
        self.assert_preserved()

    def test_missing_or_linked_catalogue_is_rejected(self):
        catalog = self.folder / "Items.lua"
        original = Path.is_symlink
        with patch.object(Path, "is_symlink", lambda path: path == catalog or original(path)):
            with self.assertRaises(SyncError):
                write_payload(self.folder, fixture_payload())
        self.assert_preserved()
        catalog.unlink()
        with self.assertRaises(SyncError):
            write_payload(self.folder, fixture_payload())
        self.assert_preserved()

    def test_catalogue_change_during_atomic_write_preserves_previous_file(self):
        real_catalog = load_catalog
        calls = []
        def changing_catalog(path):
            calls.append(path)
            return real_catalog(path) if len(calls) == 1 else [2447]
        with patch("sync.engine.load_catalog", side_effect=changing_catalog):
            with self.assertRaisesRegex(SyncError, "catalogue changed"):
                write_payload(self.folder, fixture_payload())
        self.assert_preserved()

    def test_symlink_destination_rejected_when_platform_supports_links(self):
        output = self.folder / "ExternalData.lua"
        outside = self.folder.parent / "outside.lua"
        outside.write_text("do not touch", encoding="utf-8")
        output.unlink()
        try:
            output.symlink_to(outside)
        except OSError:
            output.write_text("-- previous data\n", encoding="utf-8")
            self.skipTest("Creating symbolic links is unavailable on this host.")
        with self.assertRaises(SyncError):
            write_payload(self.folder, fixture_payload())
        self.assertEqual(outside.read_text(encoding="utf-8"), "do not touch")


if __name__ == "__main__":
    unittest.main()
