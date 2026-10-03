# AHledger import: first private version

MarketPilot Sync is a small, manually operated Windows companion. It reads the
[public AHledger API](https://ahledger.com/developers), validates every response,
and replaces one addon data file only when the whole update succeeds. The addon
loads that file on login or `/reload`. It makes no network request itself.

## Use

1. Open **MarketPilot Sync** from the desktop shortcut.
2. Explicitly select the market: ruleset, faction and region are visible. There
   is no inferred mapping from a local Forever realm to an AHledger market.
3. Select the compatible **MarketPilotDev** addon folder and click **Şimdi güncelle**.
4. Wait for success, then `/reload` in WoW and open `/mpdev external` or the
   **AHledger** tab. The first installation may require restarting the client.
5. Use **Market Watch** / **Market Report** for local scans and local history.

The companion runs on this Windows installation's existing Python 3/Tk runtime;
the desktop shortcut uses `pythonw.exe`. It is not yet a standalone executable
with a bundled runtime. To run from source: `python sync/app.py`.

The app does not upload scans, authenticate, auto-update addon code or start
scheduled downloads. A failed update leaves the last successful file intact.
Missing prices stay missing. RP/unscanned markets can legitimately contain no
observations. Changing the selected market replaces the external view only.

## Source and semantics

The provider supplies the public `/v1/markets` and
`/v1/prices/{market}/{itemID}?range=7d|30d` endpoints. It documents prices in
copper, hourly 7d buckets and daily 30d buckets. A requested window need not
contain that much history. Actual counts and elapsed coverage are displayed.
Provider medians retain fractional copper; there is no silver rounding.
See [AHledger's API documentation](https://ahledger.com/developers).

AHledger median is labelled **Provider median**, not MarketPilot clean median.
The provider's auction count is not a price-level count. The latest daily
bucket's P25–P75 describes that bucket, not a live MarketPilot Q1–Q3. Outlier
counts, percentile, trend, significance and supply classifications are not
inferred from missing provider fields. The only external comparison is:

```text
change7d = (latest.median / latest.median7d - 1) * 100
change30d = (latest.median / latest.median30d - 1) * 100
```

These comparisons need both positive, finite provider values. They do not assert
that 7d/30d local maturity requirements were met. Local Statistics,
HistoricalAnalytics and MarketSignal are unchanged.

The visible source is **AHledger — https://ahledger.com**. Data is attributed
where shown and is not represented as our own scans; see the
[provider's usage terms](https://ahledger.com/terms). Provider data quality,
sampling coverage and filtering differ from local observations and may change.

## Boundaries and format

`sync/engine.py` uses standard-library HTTPS GETs, 20-second request timeouts,
2 MiB response limits, in-memory HTTP cache expiry and a 300/minute request
ceiling. It honors Cache-Control/Age and Retry-After for 429/503. There is no
automatic retry. Fetches are sequential; a 56-item update requests two ranges
per item. The configured catalogue is read from the selected installation's
Items.lua, not a duplicated list in the desktop app. Repeated updates reuse fresh
cached responses.

Only `ExternalData.lua` in a compatible, existing MarketPilotDev or MarketPilot
folder may be written. Compatibility requires a matching TOC that loads the
data file before ExternalMarket.lua. A temporary file in the same directory is
atomically replaced after validation; failures preserve the previous export.
No WTF/SavedVariables file is opened. Development deployment also preserves an
existing ExternalData.lua instead of replacing it with the empty source stub.

The generated file assigns a typed literal to the private addon namespace:

```text
MP.ExternalPayload = {
  schema = 1, source = "AHledger", url = "https://ahledger.com",
  market, marketLabel, region, fetchedAt,
  itemIDs = {...},
  items = {
    [itemID] = {
      latest = {t, median, lowest, quantity, auctions, median7d, median30d},
      hourly = {{t, min, median, p25, p75, quantity, auctions}, ...},
      daily = {{t, min, median, p25, p75, quantity, auctions}, ...}
    }
  }
}
```

Missing primitive values are omitted. JSON text is never executed as Lua.
Unknown API fields are discarded by the importer. The consumer validates the
complete typed payload and copies its data before rendering. External rows
never enter MarketPilotDB; its schema remains 1. The import has its own format
version, not a second SavedVariables schema.

The current AHledger view is read-only both outside and inside AH. Selecting an
item displays its stored provider record. Scan, batch and cancel are disabled;
local Market Watch restores normal AH scan controls. Existing AH docking and
standalone dragging remain unchanged.

## Validation

Run `python tools/test.py` and `python tools/package.py --check` from the repo
root. Tests cover numeric/missing-data guards, identity mismatches, malformed
JSON, cache/cooldown behavior, literal serialization, atomic file preservation,
desktop concurrency/controls, provider coverage, read-only UI and local-history
isolation. Offline tests are not evidence of a rendered in-game view.

In client, validate selected market/source and observation age; compare an item
with the same AHledger market page. Verify a missing-data item stays unpriced,
external item clicks issue no AH query, local Watch still scans with AH open,
AH close retains the external window when explicitly opened, and `/reload`
loads a later successful update. Confirm local `/mpdev dbstatus` counts do not
change merely by browsing imported history. Disable the public addon while
testing local dev scans to prevent simultaneous AH requests.
