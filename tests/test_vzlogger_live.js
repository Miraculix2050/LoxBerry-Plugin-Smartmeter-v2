"use strict";

const assert = require("node:assert/strict");
const Live = require("../webfrontend/htmlauth/vzlogger_live.js");

assert.equal(Live.numericTimestamp(1700000000), 1700000000000, "epoch seconds become milliseconds");
assert.equal(Live.numericTimestamp(1700000000123), 1700000000123, "epoch milliseconds stay unchanged");
assert.equal(Live.scaledValue(12345, { display_factor: 0.001 }), 12.345, "display scaling is applied");
assert.equal(Live.chartValue(500, { category: "active_power_import" }), 500, "grid import is positive");
assert.equal(Live.chartValue(500, { category: "active_power_export" }), -500, "grid export is negative");
assert.equal(Live.chartValue(-500, { category: "active_power_total" }), -500, "signed total power is retained");

const channels = [
	{ uuid: "total", meta: { serial: "reader", channel_index: 0, unit: "W", category: "active_power_total", identifier: "1-0:16.7.0" } },
	{ uuid: "import", meta: { serial: "reader", channel_index: 1, unit: "kWh", category: "active_energy_import", identifier: "1-0:1.8.0" } },
	{ uuid: "export", meta: { serial: "reader", channel_index: 2, unit: "kWh", category: "active_energy_export", identifier: "1-0:2.8.0" } },
	{ uuid: "tariff", meta: { serial: "reader", channel_index: 3, unit: "kWh", category: "active_energy_import", identifier: "1-0:1.8.1" } },
	{ uuid: "voltage", meta: { serial: "reader", channel_index: 4, unit: "V", category: "voltage", identifier: "1-0:32.7.0" } }
];
assert.deepEqual(Array.from(Live.defaultSelection(channels)).sort(), ["export", "import", "total"], "defaults select total power and total energy only");
assert.equal(Live.chooseEnergyChannel(channels, "import").uuid, "import", "canonical total import is selected");

const ambiguous = channels.concat({ uuid: "import-copy", meta: { serial: "reader", unit: "kWh", category: "active_energy_import", identifier: "1-0:1.8.0" } });
assert.equal(Live.chooseEnergyChannel(ambiguous, "import"), null, "ambiguous counters are not guessed");

assert.deepEqual(Live.cleanPreferences({ schema: 1, channels: ["TOTAL", "missing"], energyMode: "absolute", backgroundCollection: true }, ["total"]), {
	schema: 3, channels: ["total"], energyMode: "absolute", backgroundCollection: true, historyRange: Live.DEFAULT_RANGE, historyRangeExplicit: false
}, "preferences are normalized and unavailable UUIDs are removed");
assert.equal(Live.cleanPreferences({ schema: 4, channels: [] }, []), null, "unknown preference schemas fall back to defaults");
assert.deepEqual(Live.cleanPreferences({ schema: 3, channels: ["missing"], historyRange: Live.RANGE_VALUES[3], historyRangeExplicit: true }, ["total"]), {
	schema: 3, channels: [], energyMode: "since-open", backgroundCollection: false, historyRange: Live.RANGE_VALUES[3], historyRangeExplicit: true
}, "display preferences survive removal of every selected channel");
assert.equal(Live.cleanPreferences({ schema: 2, channels: ["total"], historyRange: Live.RANGE_VALUES[3] }, ["total"]).historyRangeExplicit, true, "a non-default range from the previous schema remains an explicit choice");
assert.equal(Live.cleanPreferences({ schema: 2, channels: ["total"], historyRange: Live.DEFAULT_RANGE }, ["total"]).historyRangeExplicit, false, "the old automatic 24-hour default can migrate to dynamic selection");
assert.deepEqual(Array.from(Live.limitSelection(channels, new Set(["total", "import", "voltage"]), 2)), ["total", "import"], "restored preferences are limited to two unit groups");
assert.equal(Live.hasReadingGap(1000, 1000 + Live.GAP_INTERVAL + 1), true, "a delayed reading creates a chart gap");
assert.equal(Live.hasReadingGap(1000, 1000 + Live.GAP_INTERVAL), false, "the accepted polling window remains connected");
assert.equal(Live.isCounterReset({ category: "active_energy_export" }, 20, 19), true, "a decreasing energy counter starts a new baseline");
assert.equal(Live.isCounterReset({ category: "active_power_total" }, 20, 19), false, "ordinary power changes are not counter resets");

const previousReading = { x: 1000, y: 10, absolute: 10 };
assert.deepEqual(Live.readingDecision(previousReading, 1001, 11, "1001|11", "1000|10", { category: "active_power_total" }), {
	accept: true, rememberKey: true, gap: false, reset: false
}, "a newer reading is accepted");
assert.equal(Live.readingDecision(previousReading, 1001, 11, "1001|11", "1001|11", { category: "active_power_total" }).accept, false, "the last raw tuple is ignored");
assert.equal(Live.readingDecision(previousReading, 1000, 10, "1000|10.0", "1000|10", { category: "active_power_total" }).rememberKey, true, "an equivalent scaled tuple advances deduplication without adding history");
assert.equal(Live.readingDecision(previousReading, 999, 9, "999|9", "1000|10", { category: "active_power_total" }).accept, false, "an older reading is ignored");
assert.equal(Live.readingDecision(previousReading, 1000 + Live.GAP_INTERVAL + 1, 11, "gap|11", "1000|10", { category: "active_power_total" }).gap, true, "a delayed accepted reading requests a chart gap");
assert.equal(Live.readingDecision(previousReading, 1001, 9, "1001|9", "1000|10", { category: "active_energy_import" }).reset, true, "an accepted decreasing energy reading requests a new baseline");
assert.equal(Live.liveDataSignature({ data: [] }), Live.liveDataSignature({ data: [] }), "equivalent live responses have a stable signature");
assert.notEqual(Live.liveDataSignature({ data: [] }), Live.liveDataSignature({ data: [{ tuples: [[1, 2]] }] }), "changed live responses have a different signature");

const history = new Map([["total", [{ x: 1000, y: 12, absolute: 12, raw: 12 }, { x: 1001, y: null, absolute: null, raw: null }]]]);
const lastTuples = new Map([["total", "1|12"]]);
const energySegments = new Map([["reader", [{ start: 1000, bases: { import: 42, missing: 5 }, reset: false }]]]);
const snapshot = Live.historySnapshot("meta-1", history, lastTuples, energySegments);
const restored = Live.cleanHistorySnapshot(snapshot, ["total", "import"], "meta-1");
assert.deepEqual(restored.histories.total, [{ x: 1000, y: 12, absolute: 12, raw: null }, { x: 1001, y: null, absolute: null, raw: null }], "chart history survives compact storage round-trip");
assert.equal(restored.lastTuples.total, "1|12", "the last tuple survives reload deduplication");
assert.deepEqual(restored.energySegments.reader[0].bases, { import: 42 }, "removed channels are pruned from restored energy baselines");
assert.equal(Live.cleanHistorySnapshot(snapshot, ["total", "import"], "meta-2"), null, "history from changed metadata is rejected");

const rangeNow = Live.RANGE_VALUES[3] + 1000000;
assert.equal(Live.rangeForHistory(new Map(), rangeNow), Live.RANGE_VALUES[0], "an empty history starts with the 15-minute range");
assert.equal(Live.rangeForHistory(new Map([["total", [{ x: rangeNow - Live.RANGE_VALUES[0], y: 1 }]]]), rangeNow), Live.RANGE_VALUES[0], "up to 15 minutes of history selects 15 minutes");
assert.equal(Live.rangeForHistory(new Map([["total", [{ x: rangeNow - Live.RANGE_VALUES[0] - 1, y: 1 }]]]), rangeNow), Live.RANGE_VALUES[1], "history older than 15 minutes selects two hours");
assert.equal(Live.rangeForHistory(new Map([["total", [{ x: rangeNow - Live.RANGE_VALUES[1] - 1, y: 1 }]]]), rangeNow), Live.RANGE_VALUES[2], "history older than two hours selects 24 hours");
assert.equal(Live.rangeForHistory(new Map([["total", [{ x: rangeNow - Live.RANGE_VALUES[2] - 1, y: 1 }]]]), rangeNow), Live.RANGE_VALUES[3], "history older than 24 hours selects seven days");

const bucket = Live.mergeBucket(null, [{ x: 1, y: 5 }, { x: 2, y: 1 }, { x: 3, y: 9 }, { x: 4, y: 7 }]);
assert.deepEqual(Live.expandBucket(bucket).map(point => [point.x, point.y]), [[1,5],[2,1],[3,9],[4,7]], "bucket expansion preserves first, minimum, maximum, and last in chronological order");
const now = 10 * 24 * 60 * 60 * 1000;
const bucketStart = Math.floor((now - 20 * 60 * 1000) / 10000) * 10000;
const compacted = Live.compactHistory([
	{ x: now - 1000, y: 10 },
	{ x: bucketStart + 1, y: 5 }, { x: bucketStart + 2, y: 1 }, { x: bucketStart + 3, y: 9 }, { x: bucketStart + 4, y: 6 }, { x: bucketStart + 5, y: 7 },
	{ x: now - Live.RANGE_VALUES[3] - 1, y: 99 }
], now);
assert.equal(compacted.some(point => point.y === 99), false, "values older than seven days are removed");
assert.deepEqual(compacted.filter(point => point.x >= bucketStart && point.x < bucketStart + 10000).map(point => point.y), [5,1,9,7], "older raw values are reduced to bucket extrema and edges");
assert.equal(Live.channelFingerprint({ identifier:"1-0:1.8.0", unit:"kWh", category:"active_energy_import", display_factor:0.001, display_name:"Old" }), Live.channelFingerprint({ identifier:"1-0:1.8.0", unit:"kWh", category:"active_energy_import", display_factor:0.001, display_name:"New" }), "display-name changes retain compatible history");

const labels = { unavailable: "n/a", balanced: "balanced", moreImport: "import {value}", moreExport: "export {value}" };
assert.equal(Live.balanceText(0.0009, 0.001, labels, String), "balanced", "one Wh balance tolerance is applied");
assert.equal(Live.balanceText(0.25, 0.001, labels, String), "import 0.25", "positive balance means grid import");
assert.equal(Live.balanceText(-0.25, 0.001, labels, String), "export 0.25", "negative balance means grid export");

console.log("vzLogger live chart model tests passed");
