"""Fetch a complete, validated AHledger batch and atomically export literal Lua.

Only ExternalData.lua in an existing compatible addon folder can be written.
The engine never reads or changes WoW's WTF directory or SavedVariables.
"""

from collections import deque
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
import json
import math
import os
from pathlib import Path
import re
import tempfile
import time
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import HTTPRedirectHandler, Request, build_opener


API_BASE = "https://api.ahledger.com"
MAX_NUMBER = 2 ** 53 - 1
MAX_BODY_BYTES = 2 * 1024 * 1024
MAX_ITEMS = 200
MAX_REQUESTS_PER_MINUTE = 300
REQUEST_TIMEOUT = 20
SERIES_LIMITS = {"7d": 200, "30d": 40}
SERIES_PRICES = ("min", "median", "p25", "p75")
COUNTS = ("quantity", "auctions")
LATEST_PRICES = ("median", "lowest", "median7d", "median30d")


class SyncError(Exception):
    """A failed synchronization; the previous export remains usable."""


class CooldownError(SyncError):
    """The caller should expose the cooldown, not retry automatically."""

    def __init__(self, message, retry_at, now):
        self.retry_at = retry_at
        self.retry_after = max(0, math.ceil(retry_at - now))
        super().__init__(f"{message} Try again in {self.retry_after} seconds.")


class _NoRedirects(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise SyncError("AHledger redirected the request; no data was downloaded.")


def _text(value, context, limit=256):
    if (not isinstance(value, str) or not value or len(value) > limit
            or any(ord(char) < 32 or ord(char) == 127 or 0xD800 <= ord(char) <= 0xDFFF for char in value)):
        raise SyncError(f"{context} must be a nonempty text value without control characters.")
    return value


def _integer(value, context, minimum=0):
    if isinstance(value, bool) or not isinstance(value, int) or not minimum <= value <= MAX_NUMBER:
        raise SyncError(f"{context} must be an integer from {minimum} to {MAX_NUMBER}.")
    return value


def _price(value, context):
    if (isinstance(value, bool) or not isinstance(value, (int, float))
            or not 0 < value <= MAX_NUMBER or not math.isfinite(value)):
        raise SyncError(f"{context} must be a positive finite price no larger than {MAX_NUMBER}.")
    return value


def _object(value, context):
    if not isinstance(value, dict):
        raise SyncError(f"{context} must be an object.")
    return value


def _optional_fields(source, prices, context):
    result = {}
    for field in prices:
        if source.get(field) is not None:
            result[field] = _price(source[field], f"{context}.{field}")
    for field in COUNTS:
        if source.get(field) is not None:
            result[field] = _integer(source[field], f"{context}.{field}")
    return result


def _consistent_prices(row, pairs, context):
    for lower, upper in pairs:
        if lower in row and upper in row and row[lower] > row[upper]:
            raise SyncError(f"{context}.{lower} is greater than {upper}; the observation is contradictory.")
    return row


def _market_id(value, region):
    market_id = _text(value, "Market ID", 128)
    token = r"[a-z0-9][a-z0-9_-]*"
    match = re.fullmatch(rf"forever\.({token})\.({token})\.({token})", market_id)
    if match is None or match.group(3) != region:
        raise SyncError("Market ID must be forever.<ruleset>.<faction>.<region>, with region matching its metadata.")
    return market_id


def _label(value):
    label = _text(value, "Market label", 128)
    if len(label.encode("utf-8")) > 128 or "|" in label or not label.strip(" "):
        raise SyncError("Market label must contain 1–128 UTF-8 bytes and no WoW markup characters.")
    return label


def _iso_epoch(value, context):
    if (not isinstance(value, str) or len(value) > 40
            or not re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})", value)):
        raise SyncError(f"{context} must be an ISO timestamp with a timezone.")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        epoch = int(parsed.timestamp())
    except (ValueError, OverflowError, OSError) as error:
        raise SyncError(f"{context} is not a valid timestamp.") from error
    return _integer(epoch, context)


def _market(value):
    source = _object(value, "Market")
    result = {key: _text(source.get(key), f"Market {key}")
              for key in ("id", "game", "label", "region")}
    if result["game"] != "forever":
        raise SyncError("Select a Forever market returned by AHledger.")
    _market_id(result["id"], result["region"])
    result["label"] = _label(result["label"])
    for key in ("ruleset", "faction"):
        if source.get(key) is not None:
            result[key] = _text(source[key], f"Market {key}")
    return result


def _item_ids(values):
    if isinstance(values, (str, bytes, dict)):
        raise SyncError("Item IDs must be a list of positive integers.")
    try:
        seen = set()
        for value in values:
            seen.add(_integer(value, "Item ID", 1))
            if len(seen) > MAX_ITEMS:
                raise SyncError(f"Select between 1 and {MAX_ITEMS} configured items.")
        result = sorted(seen)
    except TypeError as error:
        raise SyncError("Item IDs must be a list of positive integers.") from error
    if not result or len(result) > MAX_ITEMS:
        raise SyncError(f"Select between 1 and {MAX_ITEMS} configured items.")
    return result


def _series(values, range_name, context, timestamps_are_iso=True):
    if not isinstance(values, list) or len(values) > SERIES_LIMITS[range_name]:
        raise SyncError(f"{context} must be an array with at most {SERIES_LIMITS[range_name]} records.")
    result = []
    seen = set()
    for index, raw in enumerate(values):
        row_context = f"{context}[{index + 1}]"
        source = _object(raw, row_context)
        timestamp = (_iso_epoch(source.get("t"), row_context + ".t") if timestamps_are_iso
                     else _integer(source.get("t"), row_context + ".t"))
        if timestamp in seen:
            raise SyncError(f"{context} contains a duplicate timestamp.")
        seen.add(timestamp)
        row = {"t": timestamp, **_optional_fields(source, SERIES_PRICES, row_context)}
        _consistent_prices(row, (("min", "median"), ("min", "p25"), ("min", "p75"),
                                ("p25", "median"), ("median", "p75"), ("p25", "p75")), row_context)
        result.append(row)
    return sorted(result, key=lambda row: row["t"])


def _price_response(raw, market_id, item_id, range_name):
    source = _object(raw, f"Item {item_id} {range_name} response")
    item = _object(source.get("item"), f"Item {item_id} metadata")
    returned_id = _integer(item.get("id"), f"Item {item_id} returned ID", 1)
    if source.get("market") != market_id or returned_id != item_id or source.get("range") != range_name:
        raise SyncError(f"Item {item_id} {range_name} response identifies a different market, item, or range.")
    rows = _series(source.get("series"), range_name, f"Item {item_id} {range_name} series")
    latest = None
    if "latest" not in source:
        raise SyncError(f"Item {item_id} {range_name} response is missing latest; null is allowed.")
    if source["latest"] is not None:
        raw_latest = _object(source["latest"], f"Item {item_id} latest")
        mapped = {"lowest": raw_latest.get("minBuyout"),
                  **{key: raw_latest.get(key) for key in ("median", "median7d", "median30d", *COUNTS)}}
        latest = {"t": _iso_epoch(raw_latest.get("observedAt"), f"Item {item_id} latest.observedAt"),
                  **_optional_fields(mapped, LATEST_PRICES, f"Item {item_id} latest")}
        _consistent_prices(latest, (("lowest", "median"),), f"Item {item_id} latest")
    return latest, rows


def _json_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON key")
        result[key] = value
    return result


def _invalid_json_constant(value):
    raise ValueError(f"invalid JSON constant {value}")


class Client:
    """Sequential, bounded HTTPS GETs; cache and rate state live in memory only.

    ``opener`` may be a callable taking (Request, timeout=...) or an object with
    ``open``. ``progress`` receives (completed_requests, total_requests, message).
    No retry, sleep, addon write, or authentication occurs during ``update``.
    """

    def __init__(self, opener=None, clock=time.time):
        self._opener = opener if opener is not None else build_opener(_NoRedirects())
        self._clock = clock
        self._cache = {}
        self._requests = deque()
        self._cooldown_until = 0

    def _cooldown(self, headers, status, now):
        delay = 60
        retry_after = headers.get("Retry-After") if headers else None
        if retry_after:
            try:
                if re.fullmatch(r"\d+", retry_after.strip()):
                    delay = int(retry_after.strip())
                else:
                    date = parsedate_to_datetime(retry_after)
                    if date.tzinfo is None:
                        date = date.replace(tzinfo=timezone.utc)
                    delay = max(0, date.timestamp() - now)
            except (ValueError, TypeError, OverflowError):
                delay = 60
        self._cooldown_until = max(self._cooldown_until, now + delay)
        return CooldownError(f"AHledger returned HTTP {status}.", self._cooldown_until, now)

    def _get(self, path):
        url = API_BASE + path
        now = self._clock()
        cached = self._cache.get(url)
        if cached and now < cached[0]:
            return cached[1]
        if now < self._cooldown_until:
            raise CooldownError("AHledger requests are cooling down.", self._cooldown_until, now)
        while self._requests and self._requests[0] <= now - 60:
            self._requests.popleft()
        if len(self._requests) >= MAX_REQUESTS_PER_MINUTE:
            raise CooldownError("The local 300-request-per-minute limit was reached.", self._requests[0] + 60, now)
        request = Request(url, headers={"Accept": "application/json", "User-Agent": "MarketPilotSync/0.1"}, method="GET")
        self._requests.append(now)
        open_call = self._opener.open if hasattr(self._opener, "open") else self._opener
        try:
            with open_call(request, timeout=REQUEST_TIMEOUT) as response:
                status = getattr(response, "status", None)
                if status is None:
                    status = response.getcode()
                if status in (429, 503):
                    raise self._cooldown(response.headers, status, self._clock())
                if status != 200:
                    raise SyncError(f"AHledger returned HTTP {status}; the update was stopped.")
                length = response.headers.get("Content-Length")
                if length is not None:
                    try:
                        declared_length = int(length)
                    except (TypeError, ValueError) as error:
                        raise SyncError("AHledger returned an invalid response size.") from error
                    if declared_length < 0 or declared_length > MAX_BODY_BYTES:
                        raise SyncError("AHledger response exceeds the 2 MiB download limit.")
                data = response.read(MAX_BODY_BYTES + 1)
                if len(data) > MAX_BODY_BYTES:
                    raise SyncError("AHledger response exceeds the 2 MiB download limit.")
                try:
                    result = json.loads(data.decode("utf-8"), object_pairs_hook=_json_object,
                                        parse_constant=_invalid_json_constant)
                except (UnicodeError, ValueError, RecursionError) as error:
                    raise SyncError("AHledger returned invalid JSON; the update was stopped.") from error
                cache_control = response.headers.get("Cache-Control", "")
                directives = {part.strip().lower().split("=", 1)[0] for part in cache_control.split(",")}
                age_match = re.search(r'(?:^|,)\s*max-age\s*=\s*"?(\d+)"?\s*(?:,|$)', cache_control, re.I)
                if age_match and "no-store" not in directives and "no-cache" not in directives:
                    try:
                        age = max(0, int(response.headers.get("Age", "0")))
                    except (ValueError, TypeError):
                        age = 0
                    remaining = max(0, int(age_match.group(1)) - age)
                    if remaining:
                        self._cache[url] = (self._clock() + remaining, result)
                return result
        except HTTPError as error:
            try:
                if error.code in (429, 503):
                    raise self._cooldown(error.headers, error.code, self._clock()) from error
                raise SyncError(f"AHledger returned HTTP {error.code}; the update was stopped.") from error
            finally:
                error.close()
        except (URLError, TimeoutError, OSError) as error:
            raise SyncError("Could not download AHledger data. Check the connection and try again.") from error

    def markets(self):
        raw = _object(self._get("/v1/markets"), "Markets response").get("markets")
        if not isinstance(raw, list) or len(raw) > 1000:
            raise SyncError("AHledger markets must be an array with at most 1000 entries.")
        result = []
        seen = set()
        for entry in raw:
            source = _object(entry, "Market entry")
            if source.get("game") != "forever":
                continue
            market = _market(source)
            if market["id"] in seen:
                raise SyncError("AHledger returned duplicate Forever market IDs.")
            seen.add(market["id"])
            result.append(market)
        return result

    def update(self, market, item_ids, progress=None):
        selected = _market(market)
        ids = _item_ids(item_ids)
        items = {}
        completed, total = 0, len(ids) * 2
        if progress:
            progress(completed, total, f"Fetching {len(ids)} items for {selected['label']}.")
        for item_id in ids:
            versions = {}
            for range_name in ("7d", "30d"):
                path = f"/v1/prices/{quote(selected['id'], safe='')}/{item_id}?range={range_name}"
                versions[range_name] = _price_response(self._get(path), selected["id"], item_id, range_name)
                completed += 1
                if progress:
                    progress(completed, total, f"Item {item_id}: {range_name} downloaded.")
            record = {"hourly": versions["7d"][1], "daily": versions["30d"][1]}
            # Each endpoint includes a current observation. Choose the newest
            # complete observation without filling gaps from the other endpoint.
            candidates = [version[0] for version in versions.values() if version[0] is not None]
            if candidates:
                record["latest"] = max(candidates, key=lambda latest: latest["t"])
            items[item_id] = record
        return {"schema": 1, "source": "AHledger", "url": "https://ahledger.com",
                "market": selected["id"], "marketLabel": selected["label"], "region": selected["region"],
                "fetchedAt": _integer(int(self._clock()), "Fetch timestamp"), "itemIDs": ids, "items": items}


def load_catalog(path):
    """Read literal itemIDs tables from the existing Items.lua, never execute Lua."""
    try:
        file = Path(path)
        if file.stat().st_size > 256 * 1024:
            raise SyncError("The item catalogue is larger than the 256 KiB limit.")
        source = file.read_text(encoding="utf-8-sig")
    except (OSError, UnicodeError) as error:
        raise SyncError(f"Could not read the configured item catalogue: {error}.") from error
    # Mask quoted strings and line comments before looking for declarations;
    # names, comments and quoted examples cannot introduce additional IDs.
    tokens = re.compile(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|--\[=*\[|\[=*\[|--[^\r\n]*')
    def mask(match):
        token = match.group()
        if re.match(r"(?:--)?\[=*\[", token):
            raise SyncError("The item catalogue uses unsupported long strings or block comments.")
        return " " * len(token)
    source = tokens.sub(mask, source)
    if '"' in source or "'" in source:
        raise SyncError("The item catalogue contains an unterminated quoted string.")
    lists = re.findall(r"\bitemIDs\s*=\s*\{([^{}]*)\}", source)
    if not lists or len(lists) != len(re.findall(r"\bitemIDs\s*=", source)):
        raise SyncError("No literal itemIDs tables were found in the item catalogue.")
    ids = []
    for table in lists:
        if not re.fullmatch(r"\s*\d+(?:\s*,\s*\d+)*\s*,?\s*", table):
            raise SyncError("The item catalogue contains a nonliteral item ID table.")
        ids.extend(int(value) for value in re.findall(r"\d+", table))
    return _item_ids(ids)


def _normalized_payload(payload):
    source = _object(payload, "External payload")
    if (type(source.get("schema")) is not int or source.get("schema") != 1
            or source.get("source") != "AHledger" or source.get("url") != "https://ahledger.com"):
        raise SyncError("External payload must use schema 1 and the AHledger source.")
    ids = _item_ids(source.get("itemIDs"))
    original_ids = source.get("itemIDs")
    if not isinstance(original_ids, list) or original_ids != ids:
        raise SyncError("External payload itemIDs must be sorted and unique.")
    raw_items = _object(source.get("items"), "External payload items")
    if any(isinstance(key, bool) or not isinstance(key, int) for key in raw_items) or set(raw_items) != set(ids):
        raise SyncError("External payload items must match the itemIDs list exactly.")
    result = {"schema": 1, "source": "AHledger", "url": "https://ahledger.com",
              **{key: _text(source.get(key), f"External payload {key}")
                 for key in ("market", "marketLabel", "region")},
              "fetchedAt": _integer(source.get("fetchedAt"), "Fetch timestamp"), "itemIDs": ids, "items": {}}
    _market_id(result["market"], result["region"])
    result["marketLabel"] = _label(result["marketLabel"])
    for item_id in ids:
        raw = _object(raw_items[item_id], f"Item {item_id}")
        record = {"hourly": _series(raw.get("hourly"), "7d", f"Item {item_id} hourly", False),
                  "daily": _series(raw.get("daily"), "30d", f"Item {item_id} daily", False)}
        if raw.get("latest") is not None:
            latest = _object(raw["latest"], f"Item {item_id} latest")
            record["latest"] = {"t": _integer(latest.get("t"), f"Item {item_id} latest.t"),
                                **_optional_fields(latest, LATEST_PRICES, f"Item {item_id} latest")}
            _consistent_prices(record["latest"], (("lowest", "median"),), f"Item {item_id} latest")
        result["items"][item_id] = record
    return result


def _lua_string(value):
    # Decimal byte escapes are fixed at three digits, so a following numeric
    # character cannot extend the escape. UTF-8 bytes remain ordinary Lua text.
    chars = []
    for char in value:
        if char in ('"', "\\"):
            chars.append("\\" + char)
        elif ord(char) < 32 or ord(char) == 127:
            chars.append(f"\\{ord(char):03d}")
        else:
            chars.append(char)
    return '"' + "".join(chars) + '"'


def _lua_literal(value, indent=0):
    if isinstance(value, str):
        return _lua_string(value)
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return repr(value)
    if isinstance(value, (list, dict)):
        if not value:
            return "{}"
        entries = []
        pairs = enumerate(value, 1) if isinstance(value, list) else value.items()
        for key, child in pairs:
            lua_key = f"[{key}]" if isinstance(key, int) else f"[{_lua_string(key)}]"
            entries.append(" " * (indent + 4) + lua_key + " = " + _lua_literal(child, indent + 4) + ",")
        return "{\n" + "\n".join(entries) + "\n" + " " * indent + "}"
    raise SyncError("External payload contains a value that cannot be exported safely.")


def serialize_payload(payload):
    """Whitelist and revalidate data before constructing literal Lua source."""
    validated = _normalized_payload(payload)
    return "-- Generated by MarketPilot Sync; AHledger external data only.\nlocal _, MP = ...\nMP.ExternalPayload = " + _lua_literal(validated) + "\n"


def validate_destination(directory):
    """Require the existing addon and its explicit external-data TOC entries."""
    path = Path(directory).absolute()
    if path.name not in ("MarketPilot", "MarketPilotDev") or not path.is_dir():
        raise SyncError("Choose an existing MarketPilot or MarketPilotDev addon folder.")
    # Reject directory aliases and linked destinations rather than follow them
    # to a different installation. A parent junction/symlink is also refused.
    if path.resolve() != path or any(parent.is_symlink() for parent in (path, *path.parents)):
        raise SyncError("The addon destination must not use symbolic links or redirected folders.")
    toc = path / (path.name + ".toc")
    output = path / "ExternalData.lua"
    consumer = path / "ExternalMarket.lua"
    catalog = path / "Items.lua"
    if toc.is_symlink() or output.is_symlink() or consumer.is_symlink() or catalog.is_symlink():
        raise SyncError("External data and addon files must not be symbolic links.")
    if not toc.is_file() or not consumer.is_file() or not catalog.is_file():
        raise SyncError("This addon installation is missing the external-data integration. Update it first.")
    try:
        if toc.stat().st_size > 256 * 1024:
            raise SyncError("The addon TOC is larger than the 256 KiB limit.")
        entries = [line.strip() for line in toc.read_text(encoding="utf-8-sig").splitlines()
                   if line.strip() and not line.lstrip().startswith("#")]
    except (OSError, UnicodeError) as error:
        raise SyncError(f"Could not read the addon TOC: {error}.") from error
    if entries.count("ExternalData.lua") != 1 or entries.count("ExternalMarket.lua") != 1:
        raise SyncError("The addon TOC must explicitly load ExternalData.lua and ExternalMarket.lua once each.")
    if entries.index("ExternalData.lua") > entries.index("ExternalMarket.lua"):
        raise SyncError("The addon TOC must load ExternalData.lua before ExternalMarket.lua.")
    if output.exists() and not output.is_file():
        raise SyncError("ExternalData.lua is not a regular file.")
    return path


def write_payload(directory, payload):
    """Atomically replace only ExternalData.lua after full validation succeeds."""
    validated = _normalized_payload(payload)
    data = serialize_payload(validated).encode("utf-8")
    directory = validate_destination(directory)
    configured = set(load_catalog(directory / "Items.lua"))
    if not set(validated["itemIDs"]).issubset(configured):
        raise SyncError("The export contains item IDs not configured in this addon installation. Update the addon first.")
    target = directory / "ExternalData.lua"
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="wb", prefix=".ExternalData-", suffix=".tmp", dir=directory, delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        # Check again before replacing in case the installation was changed
        # while the temporary export was being flushed.
        validate_destination(directory)
        if not set(validated["itemIDs"]).issubset(set(load_catalog(directory / "Items.lua"))):
            raise SyncError("The addon item catalogue changed before replacement; the previous export was preserved.")
        os.replace(temporary, target)
        temporary = None
    except OSError as error:
        raise SyncError(f"Could not replace ExternalData.lua; the previous file was preserved: {error}.") from error
    finally:
        if temporary is not None:
            try:
                temporary.unlink(missing_ok=True)
            except OSError:
                pass
    return target
