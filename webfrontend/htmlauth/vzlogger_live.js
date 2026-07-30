(function (root, factory) {
	const api = factory();
	if (typeof module === "object" && module.exports) module.exports = api;
	else root.SmartMeterLive = api;
}(typeof globalThis !== "undefined" ? globalThis : this, function () {
	"use strict";

	const STORAGE_KEY = "smartmeter-v2.vzloggerLiveCharts.v1";
	const HISTORY_STORAGE_KEY = "smartmeter-v2.vzloggerLiveHistory.v1";
	const POLL_INTERVAL = 2000;
	const MAX_POLL_INTERVAL = 30000;
	const POLL_INTERVAL_VALUES = [2000, 10000, 30000, 60000, 120000, 300000];
	const HISTORY_WRITE_INTERVAL = 10000;
	const HISTORY_WRITE_MAX_SAMPLES = 250;
	const GAP_INTERVAL = 30000;
	const GAP_MULTIPLIER = 3;
	const SAMPLE_INTERVAL_WINDOW = 31;
	const RANGE_VALUES = [15 * 60 * 1000, 2 * 60 * 60 * 1000, 24 * 60 * 60 * 1000, 7 * 24 * 60 * 60 * 1000];
	const DEFAULT_RANGE = RANGE_VALUES[2];
	const RETENTION_TIERS = [
		{ name: "10s", bucket: 10 * 1000, from: RANGE_VALUES[0], until: RANGE_VALUES[1] },
		{ name: "1m", bucket: 60 * 1000, from: RANGE_VALUES[1], until: RANGE_VALUES[2] },
		{ name: "15m", bucket: 15 * 60 * 1000, from: RANGE_VALUES[2], until: RANGE_VALUES[3] }
	];
	const CHART_BUCKETS = new Map([
		[RANGE_VALUES[0], 0],
		[RANGE_VALUES[1], 30 * 1000],
		[RANGE_VALUES[2], 5 * 60 * 1000],
		[RANGE_VALUES[3], 30 * 60 * 1000]
	]);
	const POWER_CATEGORIES = new Set(["active_power_total", "active_power_import", "active_power_export"]);
	const ENERGY_CATEGORIES = new Set(["active_energy_import", "active_energy_export"]);
	const PALETTE = ["#0072b2", "#d55e00", "#009e73", "#cc79a7", "#e69f00", "#56b4e9", "#6f4e7c", "#555555"];

	function numericTimestamp(value) {
		const number = Number(value);
		if (!Number.isFinite(number)) return null;
		return Math.abs(number) < 100000000000 ? number * 1000 : number;
	}

	function scaledValue(value, meta) {
		const number = Number(value);
		const factor = Number(meta && meta.display_factor !== undefined ? meta.display_factor : 1);
		return Number.isFinite(number) && Number.isFinite(factor) ? number * factor : null;
	}

	function category(meta) {
		return String(meta && meta.category || "unknown");
	}

	function isPower(meta) { return POWER_CATEGORIES.has(category(meta)); }
	function isEnergy(meta) { return ENERGY_CATEGORIES.has(category(meta)); }

	function chartValue(value, meta) {
		if (!Number.isFinite(value)) return null;
		if (category(meta) === "active_power_export") return -Math.abs(value);
		if (category(meta) === "active_power_import") return Math.abs(value);
		return value;
	}

	function isTotalEnergyIdentifier(identifier, direction) {
		const wanted = direction === "export" ? "2" : "1";
		return new RegExp("(?:^|:)" + wanted + "\\.8\\.0(?:\\*\\d+)?$").test(String(identifier || ""));
	}

	function chooseEnergyChannel(items, direction) {
		const wantedCategory = direction === "export" ? "active_energy_export" : "active_energy_import";
		const matches = items.filter(item => category(item.meta) === wantedCategory && isTotalEnergyIdentifier(item.meta.identifier, direction));
		const canonical = matches.filter(item => !/\*/.test(String(item.meta.identifier || "")));
		if (canonical.length === 1) return canonical[0];
		return matches.length === 1 ? matches[0] : null;
	}

	function choosePowerChannels(items) {
		const totals = items.filter(item => category(item.meta) === "active_power_total");
		if (totals.length) return [totals.sort(channelOrder)[0]];
		return items.filter(item => category(item.meta) === "active_power_import" || category(item.meta) === "active_power_export").sort(channelOrder);
	}

	function channelOrder(a, b) {
		return Number(a.meta.channel_index || 0) - Number(b.meta.channel_index || 0);
	}

	function defaultSelection(channels) {
		const selected = new Set();
		const groups = new Map();
		channels.forEach(item => {
			const serial = String(item.meta.serial || "unknown");
			if (!groups.has(serial)) groups.set(serial, []);
			groups.get(serial).push(item);
		});
		groups.forEach(items => {
			choosePowerChannels(items).forEach(item => selected.add(item.uuid));
			const imported = chooseEnergyChannel(items, "import");
			const exported = chooseEnergyChannel(items, "export");
			if (imported) selected.add(imported.uuid);
			if (exported) selected.add(exported.uuid);
		});
		if (!selected.size) {
			const units = new Set();
			channels.slice().sort(channelOrder).forEach(item => {
				const unit = String(item.meta.unit || "");
				if (units.has(unit) || units.size < 2) {
					selected.add(item.uuid);
					units.add(unit);
				}
			});
		}
		return selected;
	}

	function cleanPreferences(input, availableUuids) {
		const valid = input && [1, 2, 3, 4].includes(input.schema) && Array.isArray(input.channels);
		if (!valid) return null;
		const available = new Set(availableUuids);
		const requestedRange = Number(input.historyRange);
		const validRange = RANGE_VALUES.includes(requestedRange);
		return {
			schema: 4,
			channels: input.channels.filter(uuid => available.has(String(uuid).toLowerCase())).map(uuid => String(uuid).toLowerCase()),
			energyMode: input.energyMode === "absolute" ? "absolute" : "since-open",
			backgroundCollection: input.backgroundCollection === true,
			pollInterval: POLL_INTERVAL_VALUES.includes(Number(input.pollInterval)) ? Number(input.pollInterval) : POLL_INTERVAL,
			historyRange: validRange ? requestedRange : DEFAULT_RANGE,
			historyRangeExplicit: input.schema >= 3
				? input.historyRangeExplicit === true
				: input.schema === 2 && validRange && requestedRange !== DEFAULT_RANGE
		};
	}

	function rangeForHistory(histories, now) {
		let oldest = null;
		(histories || new Map()).forEach(points => {
			(points || []).forEach(point => {
				if (point && point.y !== null && Number.isFinite(point.x) && (oldest === null || point.x < oldest)) oldest = point.x;
			});
		});
		if (oldest === null) return RANGE_VALUES[0];
		const age = Math.max(0, now - oldest);
		return RANGE_VALUES.find(range => age <= range) || RANGE_VALUES[RANGE_VALUES.length - 1];
	}

	function limitSelection(channels, wanted, maximumUnits) {
		const result = new Set(), units = new Set(), limit = maximumUnits || 2;
		channels.slice().sort(channelOrder).forEach(item => {
			if (!wanted.has(item.uuid)) return;
			const unit = String(item.meta.unit || "");
			if (units.has(unit) || units.size < limit) {
				units.add(unit);
				result.add(item.uuid);
			}
		});
		return result;
	}

	function estimateSampleInterval(points) {
		const recent = [];
		for (let index = (points || []).length - 1; index >= 0 && recent.length <= SAMPLE_INTERVAL_WINDOW; index--) {
			const point = points[index];
			if (point && point.y !== null && Number.isFinite(point.x)) recent.push(point.x);
		}
		recent.reverse();
		const intervals = [];
		for (let index = 1; index < recent.length; index++) {
			const interval = recent[index] - recent[index - 1];
			if (interval > 0) intervals.push(interval);
		}
		if (!intervals.length) return null;
		intervals.sort((a, b) => a - b);
		const middle = Math.floor(intervals.length / 2);
		return intervals.length % 2 ? intervals[middle] : (intervals[middle - 1] + intervals[middle]) / 2;
	}

	function gapThreshold(sampleInterval) {
		return Number.isFinite(sampleInterval) && sampleInterval > 0 ? Math.max(GAP_INTERVAL, sampleInterval * GAP_MULTIPLIER) : GAP_INTERVAL;
	}

	function hasReadingGap(previousTimestamp, timestamp, sampleInterval) {
		return Number.isFinite(previousTimestamp) && Number.isFinite(timestamp) && timestamp - previousTimestamp > gapThreshold(sampleInterval);
	}

	function filterStoredGaps(points, gaps) {
		const readings = (points || []).filter(point => point && point.y !== null && Number.isFinite(point.x)).sort((a, b) => a.x - b.x);
		const sampleInterval = estimateSampleInterval(readings);
		let readingIndex = 0;
		return (gaps || []).filter(gap => gap && Number.isFinite(gap.x)).sort((a, b) => a.x - b.x).filter(gap => {
			while (readingIndex < readings.length && readings[readingIndex].x < gap.x) readingIndex += 1;
			const previousTimestamp = Number.isFinite(gap.previousX) ? gap.previousX : (readingIndex > 0 ? readings[readingIndex - 1].x : null);
			const nextTimestamp = Number.isFinite(gap.nextX) ? gap.nextX : (readingIndex < readings.length ? readings[readingIndex].x : null);
			if (!Number.isFinite(previousTimestamp) || !Number.isFinite(nextTimestamp)) return true;
			return hasReadingGap(previousTimestamp, nextTimestamp, sampleInterval);
		});
	}

	function isCounterReset(meta, previousValue, value) {
		return isEnergy(meta) && Number.isFinite(previousValue) && Number.isFinite(value) && value < previousValue;
	}

	function readingDecision(previous, x, y, key, lastKey, meta, sampleInterval) {
		if (lastKey === key) return { accept: false, rememberKey: false, gap: false, reset: false };
		if (previous && x === previous.x && y === previous.y) return { accept: false, rememberKey: true, gap: false, reset: false };
		if (previous && x < previous.x) return { accept: false, rememberKey: false, gap: false, reset: false };
		return {
			accept: true,
			rememberKey: true,
			gap: !!previous && Number.isFinite(sampleInterval) && hasReadingGap(previous.x, x, sampleInterval),
			reset: !!previous && isCounterReset(meta, previous.absolute, y)
		};
	}

	function liveDataSignature(data) {
		return JSON.stringify(data);
	}

	function latestReading(points, maximumTimestamp) {
		const hasMaximum = Number.isFinite(maximumTimestamp);
		for (let index = (points || []).length - 1; index >= 0; index--) {
			const point = points[index];
			if (point && point.y !== null && (!hasMaximum || point.x <= maximumTimestamp)) return point;
		}
		return null;
	}

	function powerPeaks(points) {
		let importPeak = null, exportPeak = null;
		(points || []).forEach(point => {
			if (!point || !Number.isFinite(point.value)) return;
			if (point.value >= 0 && (!importPeak || point.value > importPeak.value)) importPeak = point;
			if (point.value < 0 && (!exportPeak || point.value < exportPeak.value)) exportPeak = point;
		});
		return { importPeak, exportPeak };
	}

	function styleFor(uuid) {
		let hash = 0;
		for (const character of String(uuid)) hash = ((hash * 31) + character.charCodeAt(0)) >>> 0;
		return { color: PALETTE[hash % PALETTE.length], dash: [] };
	}

	function balanceText(balance, tolerance, labels, format) {
		if (!Number.isFinite(balance)) return labels.unavailable;
		if (Math.abs(balance) <= tolerance) return labels.balanced;
		return (balance > 0 ? labels.moreImport : labels.moreExport).replace("{value}", format(Math.abs(balance)));
	}

	function channelFingerprint(meta) {
		return JSON.stringify([
			String(meta && meta.identifier || ""), String(meta && meta.unit || ""),
			category(meta), Number(meta && meta.display_factor !== undefined ? meta.display_factor : 1)
		]);
	}

	function mergeBucket(bucket, points) {
		const values = points.filter(point => point && Number.isFinite(point.x) && Number.isFinite(point.y)).sort((a, b) => a.x - b.x);
		if (!values.length) return bucket || null;
		const candidates = [];
		if (bucket) [bucket.first, bucket.minimum, bucket.maximum, bucket.last].forEach(point => { if (point) candidates.push(point); });
		values.forEach(point => candidates.push({ x: point.x, y: point.y }));
		candidates.sort((a, b) => a.x - b.x);
		const hasBucketStatistics = bucket && Number.isFinite(bucket.sum) && Number.isFinite(bucket.count);
		let sum = hasBucketStatistics ? bucket.sum : 0;
		let count = hasBucketStatistics ? bucket.count : 0;
		if (bucket && !hasBucketStatistics) {
			const historical = new Map();
			[bucket.first, bucket.minimum, bucket.maximum, bucket.last].forEach(point => {
				if (point && Number.isFinite(point.x) && Number.isFinite(point.y)) historical.set(point.x + "|" + point.y, point);
			});
			historical.forEach(point => { sum += point.y; count += 1; });
		}
		values.forEach(point => {
			if (Number.isFinite(point.sampleCount)) {
				if (point.sampleCount > 0 && Number.isFinite(point.sampleSum)) { sum += point.sampleSum; count += point.sampleCount; }
			} else { sum += point.y; count += 1; }
		});
		return {
			first: candidates[0], last: candidates[candidates.length - 1],
			minimum: candidates.reduce((best, point) => point.y < best.y ? point : best, candidates[0]),
			maximum: candidates.reduce((best, point) => point.y > best.y ? point : best, candidates[0]),
			sum, count
		};
	}

	function expandBucket(bucket) {
		if (!bucket) return [];
		const unique = new Map();
		[bucket.first, bucket.minimum, bucket.maximum, bucket.last].forEach(point => {
			if (point && Number.isFinite(point.x) && Number.isFinite(point.y)) unique.set(point.x + "|" + point.y, { x: point.x, y: point.y, absolute: point.y, raw: null });
		});
		const expanded = Array.from(unique.values()).sort((a, b) => a.x - b.x);
		if (Number.isFinite(bucket.sum) && Number.isFinite(bucket.count) && bucket.count > 0 && expanded.length) {
			expanded.forEach(point => { point.sampleSum = 0; point.sampleCount = 0; });
			expanded[expanded.length - 1].sampleSum = bucket.sum;
			expanded[expanded.length - 1].sampleCount = bucket.count;
		}
		return expanded;
	}

	function aggregateChartPoints(points, meta, range) {
		const bucketSize = CHART_BUCKETS.get(range) || 0;
		if (!bucketSize) return (points || []).map(point => ({ ...point }));
		const result = [];
		let bucket = null;
		function flush() {
			if (!bucket) return;
			if (isEnergy(meta)) result.push({ ...bucket.last });
			else if (bucket.count > 0) result.push({
				x: bucket.last.x,
				y: bucket.sum / bucket.count,
				absolute: bucket.sum / bucket.count,
				raw: null
			});
			bucket = null;
		}
		(points || []).forEach(point => {
			if (!point || !Number.isFinite(point.x)) return;
			if (point.y === null) {
				flush();
				result.push({ x: point.x, y: null, absolute: null, raw: null });
				return;
			}
			if (!Number.isFinite(point.y)) return;
			const start = Math.floor(point.x / bucketSize) * bucketSize;
			if (!bucket || bucket.start !== start) { flush(); bucket = { start, sum: 0, count: 0, last: point }; }
			bucket.last = point;
			if (Number.isFinite(point.sampleCount)) {
				if (point.sampleCount > 0 && Number.isFinite(point.sampleSum)) { bucket.sum += point.sampleSum; bucket.count += point.sampleCount; }
			} else { bucket.sum += point.y; bucket.count += 1; }
		});
		flush();
		return result;
	}

	function compactHistory(points, now) {
		const retained = [], buckets = new Map(), oldest = now - RANGE_VALUES[3];
		(points || []).forEach(point => {
			if (!point || !Number.isFinite(point.x) || point.x < oldest) return;
			if (point.y === null) { retained.push({ x: point.x, y: null, absolute: null, raw: null }); return; }
			const age = now - point.x;
			const tier = RETENTION_TIERS.find(candidate => age > candidate.from && age <= candidate.until);
			if (!tier) {
				const retainedPoint = { x: point.x, y: point.y, absolute: point.y, raw: point.raw ?? null };
				if (Number.isFinite(point.sampleCount)) { retainedPoint.sampleCount = point.sampleCount; retainedPoint.sampleSum = point.sampleSum; }
				retained.push(retainedPoint);
				return;
			}
			const start = Math.floor(point.x / tier.bucket) * tier.bucket;
			const key = tier.name + "|" + start;
			buckets.set(key, { tier, start, value: mergeBucket(buckets.get(key) && buckets.get(key).value, [point]) });
		});
		buckets.forEach(entry => retained.push(...expandBucket(entry.value)));
		return retained.sort((a, b) => a.x - b.x || (a.y === null ? -1 : 1));
	}

	function historySnapshot(metadataVersion, histories, lastTuples, energySegments) {
		const packedHistories = {}, packedLastTuples = {}, packedSegments = {};
		histories.forEach((points, uuid) => {
			packedHistories[uuid] = points.map(point => [point.x, point.y]);
		});
		lastTuples.forEach((value, uuid) => { packedLastTuples[uuid] = value; });
		energySegments.forEach((segments, serial) => {
			packedSegments[serial] = segments.map(segment => [segment.start, segment.bases, segment.reset === true]);
		});
		return { schema: 1, metadataVersion: String(metadataVersion || ""), histories: packedHistories, lastTuples: packedLastTuples, energySegments: packedSegments };
	}

	function cleanHistorySnapshot(input, availableUuids, metadataVersion) {
		if (!input || input.schema !== 1 || input.metadataVersion !== String(metadataVersion || "") || !input.histories || typeof input.histories !== "object") return null;
		const available = new Set(availableUuids.map(uuid => String(uuid).toLowerCase()));
		const cleaned = { histories: {}, lastTuples: {}, energySegments: {} };
		Object.keys(input.histories).forEach(rawUuid => {
			const uuid = rawUuid.toLowerCase(), points = input.histories[rawUuid];
			if (!available.has(uuid) || !Array.isArray(points)) return;
			cleaned.histories[uuid] = points.filter(point => Array.isArray(point) && Number.isFinite(point[0]) && (point[1] === null || Number.isFinite(point[1]))).map(point => ({ x: point[0], y: point[1], absolute: point[1], raw: null }));
		});
		if (input.lastTuples && typeof input.lastTuples === "object") Object.keys(input.lastTuples).forEach(rawUuid => {
			const uuid = rawUuid.toLowerCase();
			if (available.has(uuid) && typeof input.lastTuples[rawUuid] === "string") cleaned.lastTuples[uuid] = input.lastTuples[rawUuid];
		});
		if (input.energySegments && typeof input.energySegments === "object") Object.keys(input.energySegments).forEach(serial => {
			const segments = input.energySegments[serial];
			if (!Array.isArray(segments)) return;
			cleaned.energySegments[serial] = segments.filter(segment => Array.isArray(segment) && Number.isFinite(segment[0]) && segment[1] && typeof segment[1] === "object").map(segment => {
				const bases = {};
				Object.keys(segment[1]).forEach(rawUuid => {
					const uuid = rawUuid.toLowerCase(), value = segment[1][rawUuid];
					if (available.has(uuid) && Number.isFinite(value)) bases[uuid] = value;
				});
				return { start: segment[0], bases, reset: segment[2] === true };
			});
		});
		return cleaned;
	}

	function pollDelay(failures, interval) {
		const selected = POLL_INTERVAL_VALUES.includes(Number(interval)) ? Number(interval) : POLL_INTERVAL;
		return failures > 0 ? Math.max(selected, Math.min(selected * Math.pow(2, failures), MAX_POLL_INTERVAL)) : selected;
	}

	return {
		STORAGE_KEY, HISTORY_STORAGE_KEY, POLL_INTERVAL, MAX_POLL_INTERVAL, POLL_INTERVAL_VALUES, HISTORY_WRITE_INTERVAL, HISTORY_WRITE_MAX_SAMPLES, GAP_INTERVAL, GAP_MULTIPLIER, SAMPLE_INTERVAL_WINDOW, RANGE_VALUES, DEFAULT_RANGE, RETENTION_TIERS, CHART_BUCKETS,
		numericTimestamp, scaledValue, category, isPower, isEnergy, chartValue,
		chooseEnergyChannel, choosePowerChannels, defaultSelection, cleanPreferences, rangeForHistory,
		limitSelection, estimateSampleInterval, gapThreshold, hasReadingGap, filterStoredGaps, isCounterReset, readingDecision, liveDataSignature, latestReading, powerPeaks, styleFor, balanceText,
		historySnapshot, cleanHistorySnapshot, channelFingerprint, mergeBucket, expandBucket, compactHistory, aggregateChartPoints, pollDelay
	};
}));

(function () {
	"use strict";
	if (typeof window === "undefined" || typeof document === "undefined") return;
	const Live = window.SmartMeterLive;
	const i18n = document.getElementById("i18n").dataset;
	const locale = i18n.locale === "de" ? "de-DE" : "en-US";
	const languageQuery = "&lang=" + encodeURIComponent(i18n.locale);
	let metadataVersion = "";
	let metadata = { channels: {} };
	let channels = [];
	let selected = new Set();
	let energyMode = "since-open";
	let backgroundCollection = false;
	let pollInterval = Live.POLL_INTERVAL;
	let historyRange = Live.DEFAULT_RANGE;
	let historyRangeExplicit = false;
	let currentData = null;
	let lastLiveDataSignature = null;
	let timer = null;
	let stopped = false;
	let refreshing = false;
	let pollFailures = 0;
	let chart = null;
	let historyDb = null;
	let historyStorageAvailable = false;
	let historyInitialized = false;
	let lastHistoryCleanup = 0;
	let lastMemoryCompaction = 0;
	let memoryCompactionQueue = [];
	let memoryCompactionScheduled = false;
	let historyWriteQueue = Promise.resolve();
	let pendingHistorySamples = [];
	let pendingHistoryGaps = [];
	let historyFlushTimer = null;
	const histories = new Map();
	const lastTuple = new Map();
	const energySegments = new Map();
	const numberFormats = new Map();

	function esc(value) { return String(value ?? "").replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c])); }
	function diagnosticHtml(message, hint) { return esc(message) + (hint ? '<span class="diagnostic-hint">' + esc(hint) + "</span>" : ""); }
	function readableName(value) { return String(value || i18n.unnamed).replace(/_/g, " "); }
	function formatNumber(value, digits) {
		const maximumFractionDigits = digits === undefined ? 6 : digits;
		if (!numberFormats.has(maximumFractionDigits)) numberFormats.set(maximumFractionDigits, new Intl.NumberFormat(locale, { maximumFractionDigits, useGrouping: false }));
		return numberFormats.get(maximumFractionDigits).format(value);
	}
	function channelUuid(channel) { return String(channel.uuid || channel.id || "").toLowerCase(); }
	function channelNumber(meta, index) { return Number.isInteger(meta.channel_index) ? meta.channel_index : index; }
	function channelName(item) {
		const catalog = i18n.locale === "de" ? item.meta.catalog_name_de : item.meta.catalog_name_en;
		return item.meta.display_name || catalog || readableName(item.meta.name || item.meta.identifier || item.uuid);
	}
	function displayValue(value, meta) {
		const scaled = Live.scaledValue(value, meta);
		const unit = String(meta.unit || "");
		if (scaled === null) return esc(value) + (unit ? " " + esc(unit) : "");
		const title = Number(meta.display_factor ?? 1) !== 1 ? ' title="' + esc(i18n.rawValue) + ": " + esc(value) + '"' : "";
		return "<span" + title + ">" + esc(formatNumber(scaled)) + (unit ? " " + esc(unit) : "") + "</span>";
	}
	function timestampText(value) {
		const milliseconds = Live.numericTimestamp(value);
		if (milliseconds === null) return esc(value);
		const date = new Date(milliseconds);
		const readable = Number.isNaN(date.getTime()) ? i18n.invalidTime : date.toLocaleString(locale, { dateStyle: "medium", timeStyle: "medium" });
		return '<span class="raw-time">' + esc(value) + "</span> (" + esc(readable) + ")";
	}

	async function loadMetadata() {
		const previousVersion = metadataVersion;
		const response = await fetch("?meta=1" + languageQuery, { cache: "no-store" });
		if (!response.ok) throw new Error(i18n.metadataFailed);
		metadata = await response.json();
		metadata.channels = metadata.channels || {};
		metadataVersion = String(metadata.version || "");
		channels = Object.keys(metadata.channels).map(uuid => ({ uuid: uuid.toLowerCase(), meta: metadata.channels[uuid] })).sort((a, b) => channelNumber(a.meta, 0) - channelNumber(b.meta, 0));
		if (historyDb && previousVersion && previousVersion !== metadataVersion) await reconcileHistoryChannels();
		loadPreferences();
		renderControls();
	}

	function loadPreferences() {
		let parsed = null;
		try { parsed = JSON.parse(localStorage.getItem(Live.STORAGE_KEY) || "null"); } catch (_) { parsed = null; }
		const cleaned = Live.cleanPreferences(parsed, channels.map(item => item.uuid));
		if (cleaned) {
			selected = cleaned.channels.length ? Live.limitSelection(channels, new Set(cleaned.channels), 2) : Live.defaultSelection(channels);
			energyMode = cleaned.energyMode;
			backgroundCollection = cleaned.backgroundCollection;
			pollInterval = cleaned.pollInterval;
			historyRange = cleaned.historyRange;
			historyRangeExplicit = cleaned.historyRangeExplicit;
		} else {
			selected = Live.defaultSelection(channels);
			energyMode = "since-open";
			backgroundCollection = false;
			pollInterval = Live.POLL_INTERVAL;
			historyRange = Live.DEFAULT_RANGE;
			historyRangeExplicit = false;
		}
		savePreferences();
	}

	function savePreferences() {
		try { localStorage.setItem(Live.STORAGE_KEY, JSON.stringify({ schema: 4, channels: Array.from(selected), energyMode, backgroundCollection, pollInterval, historyRange, historyRangeExplicit })); } catch (_) { /* Browser storage may be unavailable. */ }
	}

	function selectInitialHistoryRange() {
		if (historyRangeExplicit) return;
		historyRange = Live.rangeForHistory(histories, Date.now());
		savePreferences();
		renderControls();
	}

	function collapsibleStorageKey(element) {
		return "smartmeter-vzlogger-live-collapsible:" + window.location.pathname + ":" + element.id;
	}

	function initializeCollapsiblePersistence() {
		document.querySelectorAll("details.persisted-collapsible[id]").forEach(element => {
			try {
				const state = localStorage.getItem(collapsibleStorageKey(element));
				if (state === "open") element.open = true;
				else if (state === "closed") element.open = false;
			} catch (_) { /* Browser storage may be unavailable. */ }
			element.addEventListener("toggle", () => {
				try { localStorage.setItem(collapsibleStorageKey(element), element.open ? "open" : "closed"); } catch (_) { /* Browser storage may be unavailable. */ }
			});
		});
	}

	function requestResult(request) {
		return new Promise((resolve, reject) => {
			request.onsuccess = () => resolve(request.result);
			request.onerror = () => reject(request.error || new Error(i18n.historyUnavailable));
		});
	}

	function transactionDone(transaction) {
		return new Promise((resolve, reject) => {
			transaction.oncomplete = () => resolve();
			transaction.onerror = () => reject(transaction.error || new Error(i18n.historyUnavailable));
			transaction.onabort = () => reject(transaction.error || new Error(i18n.historyUnavailable));
		});
	}

	function openHistoryDatabase() {
		return new Promise((resolve, reject) => {
			if (!window.indexedDB) { reject(new Error(i18n.historyUnavailable)); return; }
			const request = indexedDB.open("smartmeter-v2-vzlogger-live", 1);
			request.onupgradeneeded = () => {
				const database = request.result;
				const readings = database.createObjectStore("readings", { keyPath: ["uuid", "x"] });
				readings.createIndex("by_x", "x");
				const buckets = database.createObjectStore("buckets", { keyPath: ["uuid", "tier", "start"] });
				buckets.createIndex("by_tier_start", ["tier", "start"]);
				const gaps = database.createObjectStore("gaps", { keyPath: ["uuid", "x"] });
				gaps.createIndex("by_x", "x");
				database.createObjectStore("meta", { keyPath: "key" });
			};
			request.onsuccess = () => resolve(request.result);
			request.onerror = () => reject(request.error || new Error(i18n.historyUnavailable));
			request.onblocked = () => reject(new Error(i18n.historyUnavailable));
		});
	}

	function showHistoryStorageMessage(message, error) {
		const element = document.getElementById("history-storage-status");
		element.textContent = message || "";
		element.className = error ? "status error" : "status";
	}

	async function deleteChannelHistory(uuid) {
		if (!historyDb) return;
		const transaction = historyDb.transaction(["readings", "buckets", "gaps"], "readwrite");
		const done = transactionDone(transaction);
		transaction.objectStore("readings").delete(IDBKeyRange.bound([uuid, 0], [uuid, Number.MAX_SAFE_INTEGER]));
		transaction.objectStore("buckets").delete(IDBKeyRange.bound([uuid, "", 0], [uuid, "\uffff", Number.MAX_SAFE_INTEGER]));
		transaction.objectStore("gaps").delete(IDBKeyRange.bound([uuid, 0], [uuid, Number.MAX_SAFE_INTEGER]));
		await done;
	}

	async function reconcileHistoryChannels() {
		const current = {};
		channels.forEach(item => { current[item.uuid] = Live.channelFingerprint(item.meta); });
		const transaction = historyDb.transaction("meta", "readonly");
		const readDone = transactionDone(transaction);
		const stored = await requestResult(transaction.objectStore("meta").get("channelFingerprints"));
		await readDone;
		const previous = stored && stored.value && typeof stored.value === "object" ? stored.value : {};
		for (const uuid of Object.keys(previous)) {
			if (!current[uuid] || current[uuid] !== previous[uuid]) {
				await deleteChannelHistory(uuid);
				histories.delete(uuid); lastTuple.delete(uuid);
			}
		}
		const write = historyDb.transaction("meta", "readwrite");
		const writeDone = transactionDone(write);
		write.objectStore("meta").put({ key: "channelFingerprints", value: current });
		await writeDone;
	}

	function groupedBuckets(samples) {
		const grouped = new Map();
		Live.RETENTION_TIERS.forEach(tier => samples.forEach(sample => {
			const start = Math.floor(sample.x / tier.bucket) * tier.bucket;
			const key = sample.uuid + "|" + tier.name + "|" + start;
			if (!grouped.has(key)) grouped.set(key, { uuid: sample.uuid, tier: tier.name, start, points: [] });
			grouped.get(key).points.push(sample);
		}));
		return grouped;
	}

	async function persistSamples(samples, gaps) {
		if (!historyDb || (!samples.length && !gaps.length)) return;
		const transaction = historyDb.transaction(["readings", "buckets", "gaps"], "readwrite");
		const done = transactionDone(transaction);
		const readingsStore = transaction.objectStore("readings"), bucketStore = transaction.objectStore("buckets"), gapStore = transaction.objectStore("gaps");
		samples.forEach(sample => readingsStore.put({ uuid: sample.uuid, x: sample.x, y: sample.y }));
		gaps.forEach(gap => gapStore.put(gap));
		groupedBuckets(samples).forEach(entry => {
			const request = bucketStore.get([entry.uuid, entry.tier, entry.start]);
			request.onsuccess = () => {
				const existing = request.result || null;
				const merged = Live.mergeBucket(existing, entry.points);
				bucketStore.put({ uuid: entry.uuid, tier: entry.tier, start: entry.start, ...merged });
			};
		});
		await done;
	}

	function deleteByIndex(index, range) {
		return new Promise((resolve, reject) => {
			const request = index.openKeyCursor(range);
			request.onsuccess = () => {
				const cursor = request.result;
				if (!cursor) { resolve(); return; }
				index.objectStore.delete(cursor.primaryKey);
				cursor.continue();
			};
			request.onerror = () => reject(request.error || new Error(i18n.historyUnavailable));
		});
	}

	async function cleanupHistoryDatabase(now) {
		if (!historyDb) return;
		const transaction = historyDb.transaction(["readings", "buckets", "gaps"], "readwrite");
		const done = transactionDone(transaction);
		const jobs = [
			deleteByIndex(transaction.objectStore("readings").index("by_x"), IDBKeyRange.upperBound(now - Live.RANGE_VALUES[0], true)),
			deleteByIndex(transaction.objectStore("gaps").index("by_x"), IDBKeyRange.upperBound(now - Live.RANGE_VALUES[3], true))
		];
		Live.RETENTION_TIERS.forEach(tier => jobs.push(deleteByIndex(
			transaction.objectStore("buckets").index("by_tier_start"),
			IDBKeyRange.bound([tier.name, 0], [tier.name, now - tier.until], false, true)
		)));
		await Promise.all(jobs);
		await done;
		lastHistoryCleanup = now;
	}

	async function persistWithRecovery(samples, gaps) {
		try { await persistSamples(samples, gaps); }
		catch (_) {
			try { await cleanupHistoryDatabase(Date.now()); await persistSamples(samples, gaps); }
			catch (error) { historyStorageAvailable = false; showHistoryStorageMessage(i18n.historyUnavailable, true); throw error; }
		}
		if (Date.now() - lastHistoryCleanup > 60000) await cleanupHistoryDatabase(Date.now());
	}

	function queueHistoryWrite(samples, gaps) {
		if (!historyStorageAvailable || !samples.length) return;
		pendingHistorySamples.push(...samples);
		pendingHistoryGaps.push(...gaps);
		if (pendingHistorySamples.length >= Live.HISTORY_WRITE_MAX_SAMPLES) flushHistoryWrites();
		else if (!historyFlushTimer) historyFlushTimer = window.setTimeout(flushHistoryWrites, Live.HISTORY_WRITE_INTERVAL);
	}

	function flushHistoryWrites() {
		if (historyFlushTimer) window.clearTimeout(historyFlushTimer);
		historyFlushTimer = null;
		if (!historyStorageAvailable || !pendingHistorySamples.length) return historyWriteQueue;
		const samples = pendingHistorySamples.splice(0);
		const gaps = pendingHistoryGaps.splice(0);
		historyWriteQueue = historyWriteQueue.then(() => persistWithRecovery(samples, gaps)).catch(() => {});
		return historyWriteQueue;
	}

	async function migrateSessionHistory() {
		let parsed = null;
		try { parsed = JSON.parse(sessionStorage.getItem(Live.HISTORY_STORAGE_KEY) || "null"); } catch (_) { parsed = null; }
		const cleaned = Live.cleanHistorySnapshot(parsed, channels.map(item => item.uuid), metadataVersion);
		if (!cleaned) return;
		for (const uuid of Object.keys(cleaned.histories)) {
			const retained = cleaned.histories[uuid].filter(point => point.x >= Date.now() - Live.RANGE_VALUES[3]);
			const samples = retained.filter(point => point.y !== null).map(point => ({ uuid, x: point.x, y: point.y }));
			const gaps = retained.filter(point => point.y === null).map(point => ({ uuid, x: point.x }));
			for (let offset = 0; offset < samples.length; offset += 250) await persistSamples(samples.slice(offset, offset + 250), offset === 0 ? gaps : []);
			if (!samples.length && gaps.length) await persistSamples([], gaps);
		}
		try { sessionStorage.removeItem(Live.HISTORY_STORAGE_KEY); } catch (_) { /* The successful IndexedDB import remains authoritative. */ }
	}

	async function loadChannelHistory(uuid, now) {
		const transaction = historyDb.transaction(["readings", "buckets", "gaps"], "readonly");
		const done = transactionDone(transaction);
		const readingsStore = transaction.objectStore("readings"), bucketStore = transaction.objectStore("buckets"), gapStore = transaction.objectStore("gaps");
		const requests = [requestResult(readingsStore.getAll(IDBKeyRange.bound([uuid, now - Live.RANGE_VALUES[0]], [uuid, now])))];
		Live.RETENTION_TIERS.forEach(tier => requests.push(requestResult(bucketStore.getAll(IDBKeyRange.bound(
			[uuid, tier.name, now - tier.until], [uuid, tier.name, now - tier.from]
		)))));
		requests.push(requestResult(gapStore.getAll(IDBKeyRange.bound([uuid, now - Live.RANGE_VALUES[3]], [uuid, now]))));
		const values = await Promise.all(requests);
		await done;
		const points = values[0].map(record => ({ x: record.x, y: record.y, absolute: record.y, raw: null }));
		for (let index = 1; index <= Live.RETENTION_TIERS.length; index++) values[index].forEach(record => points.push(...Live.expandBucket(record)));
		Live.filterStoredGaps(points, values[values.length - 1]).forEach(gap => points.push({ x: gap.x, y: null, absolute: null, raw: null }));
		const unique = new Map();
		points.forEach(point => unique.set(point.x + "|" + String(point.y), point));
		return Live.compactHistory(Array.from(unique.values()), now);
	}

	function rebuildEnergySegments() {
		energySegments.clear();
		channels.filter(item => Live.isEnergy(item.meta)).forEach(item => {
			const serial = String(item.meta.serial || "unknown");
			const points = (histories.get(item.uuid) || []).filter(point => point.y !== null).sort((a, b) => a.x - b.x);
			if (!points.length) return;
			if (!energySegments.has(serial)) energySegments.set(serial, [{ start: points[0].x, bases: {}, reset: false }]);
			energySegments.get(serial)[0].bases[item.uuid] = points[0].absolute;
			for (let index = 1; index < points.length; index++) if (Live.isCounterReset(item.meta, points[index - 1].absolute, points[index].absolute)) registerEnergyReset(serial, points[index].x, item.uuid, points[index].absolute);
		});
	}

	async function initializeHistoryStorage() {
		try {
			historyDb = await openHistoryDatabase();
			historyDb.onversionchange = () => { historyDb.close(); historyStorageAvailable = false; showHistoryStorageMessage(i18n.historyUnavailable, true); };
			historyStorageAvailable = true;
			await reconcileHistoryChannels();
			await migrateSessionHistory();
			await cleanupHistoryDatabase(Date.now());
			for (let offset = 0; offset < channels.length; offset += 4) {
				const batch = channels.slice(offset, offset + 4);
				const loaded = await Promise.all(batch.map(item => loadChannelHistory(item.uuid, Date.now())));
				batch.forEach((item, index) => histories.set(item.uuid, loaded[index]));
			}
			rebuildEnergySegments();
			showHistoryStorageMessage("", false);
		} catch (_) {
			historyStorageAvailable = false;
			showHistoryStorageMessage(i18n.historyUnavailable, true);
		}
	}

	async function clearPersistedHistory() {
		const storageWasAvailable = historyStorageAvailable;
		await flushHistoryWrites();
		historyStorageAvailable = false;
		await historyWriteQueue;
		histories.clear(); lastTuple.clear(); energySegments.clear();
		if (historyDb) {
			const transaction = historyDb.transaction(["readings", "buckets", "gaps"], "readwrite");
			const done = transactionDone(transaction);
			transaction.objectStore("readings").clear(); transaction.objectStore("buckets").clear(); transaction.objectStore("gaps").clear();
			await done;
		}
		try { sessionStorage.removeItem(Live.HISTORY_STORAGE_KEY); } catch (_) { /* Ignore unavailable previous storage. */ }
		historyStorageAvailable = storageWasAvailable;
		if (currentData) ingest(currentData);
		updateChart();
	}

	function renderControls() {
		const groups = new Map();
		channels.forEach(item => {
			const serial = String(item.meta.serial || "unknown");
			if (!groups.has(serial)) groups.set(serial, []);
			groups.get(serial).push(item);
		});
		const output = [];
		groups.forEach((items, serial) => {
			output.push('<fieldset><legend>' + esc(items[0].meta.head_name || serial) + '</legend><div class="channel-choices">');
			items.forEach(item => {
				output.push('<label><input type="checkbox" data-channel="' + esc(item.uuid) + '"' + (selected.has(item.uuid) ? " checked" : "") + '><span>' + esc(i18n.channel) + " " + esc(channelNumber(item.meta, 0)) + " – " + esc(channelName(item)) + '</span><small>' + esc(item.meta.unit || "—") + "</small></label>");
			});
			output.push("</div></fieldset>");
		});
		document.getElementById("channel-choices").innerHTML = output.join("");
		document.getElementById("energy-mode").value = energyMode;
		document.getElementById("history-range").value = String(historyRange);
		document.getElementById("poll-interval").value = String(pollInterval);
		document.getElementById("background-collection").checked = backgroundCollection;
		document.querySelectorAll("input[data-channel]").forEach(input => input.addEventListener("change", changeSelection));
	}

	function changeSelection(event) {
		const uuid = event.currentTarget.dataset.channel;
		if (event.currentTarget.checked) {
			const candidate = metadata.channels[uuid] || {};
			const units = new Set(Array.from(selected).map(id => String((metadata.channels[id] || {}).unit || "")));
			units.add(String(candidate.unit || ""));
			if (units.size > 2) {
				event.currentTarget.checked = false;
				showChoiceMessage(i18n.maxUnits, true);
				return;
			}
			selected.add(uuid);
		} else selected.delete(uuid);
		if (!selected.size) {
			event.currentTarget.checked = true;
			selected.add(uuid);
			showChoiceMessage(i18n.oneChannel, true);
			return;
		}
		showChoiceMessage("", false);
		savePreferences();
		updateChart();
	}

	function showChoiceMessage(message, error) {
		const element = document.getElementById("chart-choice-message");
		element.textContent = message;
		element.className = error ? "status error" : "status";
	}

	function resetDefaults() {
		selected = Live.defaultSelection(channels);
		energyMode = "since-open";
		backgroundCollection = false;
		pollInterval = Live.POLL_INTERVAL;
		historyRange = Live.rangeForHistory(histories, Date.now());
		historyRangeExplicit = false;
		savePreferences();
		renderControls();
		showChoiceMessage("", false);
		updateChart();
	}

	function registerEnergyReset(serial, timestamp, resetUuid, newValue) {
		const segments = energySegments.get(serial) || [];
		if (segments.length && segments[segments.length - 1].start === timestamp) return;
		const bases = {};
		channels.filter(item => String(item.meta.serial || "unknown") === serial && Live.isEnergy(item.meta)).forEach(item => {
			const history = histories.get(item.uuid) || [];
			const latest = Live.latestReading(history, timestamp);
			if (latest) bases[item.uuid] = latest.absolute;
		});
		bases[resetUuid] = newValue;
		segments.push({ start: timestamp, bases, reset: true });
		energySegments.set(serial, segments);
	}

	function scheduleNextMemoryCompaction() {
		if (memoryCompactionScheduled || !memoryCompactionQueue.length) return;
		memoryCompactionScheduled = true;
		const compactNext = () => {
			memoryCompactionScheduled = false;
			const uuid = memoryCompactionQueue.shift();
			const points = histories.get(uuid);
			if (points) histories.set(uuid, Live.compactHistory(points, Date.now()));
			scheduleNextMemoryCompaction();
		};
		if (typeof window.requestIdleCallback === "function") window.requestIdleCallback(compactNext, { timeout: 1000 });
		else window.setTimeout(compactNext, 0);
	}

	function scheduleMemoryCompaction(now) {
		if (now - lastMemoryCompaction <= 60000 || memoryCompactionQueue.length || memoryCompactionScheduled) return;
		lastMemoryCompaction = now;
		memoryCompactionQueue = Array.from(histories.keys());
		scheduleNextMemoryCompaction();
	}

	function ingest(data) {
		const liveChannels = Array.isArray(data && data.data) ? data.data : (Array.isArray(data) ? data : []);
		let changed = false;
		const samples = [], gaps = [];
		liveChannels.forEach((channel, index) => {
			const uuid = channelUuid(channel);
			const meta = metadata.channels[uuid] || {};
			const tuples = Array.isArray(channel.tuples) ? channel.tuples : [];
			tuples.forEach(tuple => {
				if (!Array.isArray(tuple)) return;
				const x = Live.numericTimestamp(tuple[0]);
				const y = Live.scaledValue(tuple[1], meta);
				if (x === null || y === null) return;
				const key = String(tuple[0]) + "|" + String(tuple[1]);
				const history = histories.get(uuid) || [];
				const previous = Live.latestReading(history);
				const decision = Live.readingDecision(previous, x, y, key, lastTuple.get(uuid), meta, Live.estimateSampleInterval(history));
				if (!decision.accept) {
					if (decision.rememberKey) lastTuple.set(uuid, key);
					return;
				}
				if (Live.isEnergy(meta) && !energySegments.has(String(meta.serial || "unknown"))) energySegments.set(String(meta.serial || "unknown"), [{ start: x, bases: { [uuid]: y }, reset: false }]);
				if (decision.gap) {
					const gap = { uuid, x: previous.x + 1, previousX: previous.x, nextX: x };
					history.push({ x: gap.x, y: null, absolute: null, raw: null }); gaps.push(gap);
				}
				if (decision.reset) registerEnergyReset(String(meta.serial || "unknown"), x, uuid, y);
				history.push({ x, y, absolute: y, raw: tuple[1] });
				histories.set(uuid, history);
				lastTuple.set(uuid, key);
				samples.push({ uuid, x, y });
				changed = true;
			});
		});
		if (changed) {
			const now = Date.now();
			scheduleMemoryCompaction(now);
			queueHistoryWrite(samples, gaps);
		}
		return changed;
	}

	function renderTable(data) {
		if (data && data.error) throw new Error(data.error);
		const liveChannels = Array.isArray(data && data.data) ? data.data : (Array.isArray(data) ? data : []);
		if (!liveChannels.length) { document.getElementById("state").innerHTML = '<div class="empty">' + diagnosticHtml(i18n.noChannels, i18n.noChannelsHint) + "</div>"; return; }
		const groups = new Map();
		liveChannels.forEach((channel, index) => {
			const uuid = channelUuid(channel), meta = metadata.channels[uuid] || {}, serial = meta.serial || "unknown";
			if (!groups.has(serial)) groups.set(serial, { name: meta.head_name || serial, serial, channels: [] });
			groups.get(serial).channels.push({ channel, meta, index, uuid });
		});
		const output = [];
		groups.forEach(group => {
			output.push("<section><h2>" + esc(group.name) + '<span class="serial">' + esc(i18n.readingHead) + ": " + esc(group.serial) + "</span></h2>");
			output.push('<div class="table-wrap"><table><thead><tr><th class="time">' + esc(i18n.timestamp) + "</th><th>" + esc(i18n.value) + "</th></tr></thead><tbody>");
			group.channels.sort((a,b) => channelNumber(a.meta,a.index)-channelNumber(b.meta,b.index)).forEach(item => {
				const number = channelNumber(item.meta,item.index), identifier = item.meta.identifier || item.channel.identifier || "";
				output.push('<tr class="channel-heading"><th colspan="2"><span class="channel-title">' + esc(i18n.channel) + " " + esc(number) + " - " + esc(channelName(item)) + '</span><span class="channel-meta">OBIS: ' + esc(identifier || "-") + " | UUID: " + esc(item.uuid || "-") + "</span></th></tr>");
				const tuples = Array.isArray(item.channel.tuples) ? item.channel.tuples : [];
				if (!tuples.length) output.push('<tr><td colspan="2" class="empty">' + esc(i18n.noReading) + "</td></tr>");
				else tuples.forEach(tuple => output.push("<tr><td>" + timestampText(Array.isArray(tuple) ? tuple[0] : "") + '</td><td class="value">' + displayValue(Array.isArray(tuple) ? tuple[1] : tuple, item.meta) + "</td></tr>"));
			});
			output.push("</tbody></table></div></section>");
		});
		output.push('<p class="status">vzLogger ' + esc(data.version || "") + (data.generator ? " | " + esc(data.generator) : "") + "</p>");
		document.getElementById("state").innerHTML = output.join("");
	}

	function datasetFor(item) {
		const cutoff = Date.now() - historyRange;
		const meta = item.meta, style = Live.styleFor(item.uuid);
		const history = Live.aggregateChartPoints((histories.get(item.uuid) || []).filter(point => point.x >= cutoff), meta, historyRange);
		const points = [];
		const resetStarts = (energySegments.get(String(meta.serial || "unknown")) || []).filter(segment => segment.reset).map(segment => segment.start);
		let previousX = null, relativeBase = null;
		history.forEach(point => {
			if (Live.isEnergy(meta) && resetStarts.some(start => previousX !== null && previousX < start && point.x >= start)) {
				points.push({ x: point.x - 1, y: null, absolute: null }); relativeBase = null;
			}
			if (point.y !== null && Live.isEnergy(meta) && energyMode === "since-open" && relativeBase === null) relativeBase = point.absolute;
			points.push({
				x: point.x,
				y: point.y === null ? null : (Live.isEnergy(meta) && energyMode === "since-open" ? point.absolute - relativeBase : Live.chartValue(point.y, meta)),
				absolute: point.absolute
			});
			previousX = point.x;
		});
		return {
			label: (meta.head_name ? meta.head_name + " – " : "") + channelName(item),
			data: points,
			yAxisID: "unit-" + String(meta.unit || "value"), borderColor: colorWithAlpha(style.color, 0.95), backgroundColor: colorWithAlpha(style.color, 0.04),
			fill: Live.isPower(meta) ? { target: "origin" } : false,
			borderDash: style.dash, borderWidth: 2, pointRadius: 0, pointHoverRadius: 4, pointHitRadius: 8, spanGaps: false,
			cubicInterpolationMode: "monotone", tension: 0.15, metaInfo: meta, uuid: item.uuid, order: 0
		};
	}

	function updateChart() {
		if (typeof Chart === "undefined") return;
		const items = channels.filter(item => selected.has(item.uuid));
		const visibility = new Map();
		if (chart) chart.data.datasets.forEach((dataset, index) => visibility.set(dataset.uuid, chart.isDatasetVisible(index)));
		const datasets = items.map(datasetFor);
		const units = [];
		datasets.forEach(dataset => { const unit = String(dataset.metaInfo.unit || ""); if (!units.includes(unit)) units.push(unit); });
		const now = Date.now(), cutoff = now - historyRange;
		const scales = { x: { type: "linear", min: cutoff, max: now, title: { display: true, text: i18n.timeAxis }, ticks: { callback: value => new Date(value).toLocaleString(locale, historyRange > Live.RANGE_VALUES[2] ? { month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit" } : { hour: "2-digit", minute: "2-digit", second: "2-digit" }), maxRotation: 0 } } };
		units.forEach((unit, index) => {
			const unitDatasets = datasets.filter(dataset => String(dataset.metaInfo.unit || "") === unit);
			const power = unitDatasets.some(dataset => Live.isPower(dataset.metaInfo));
			const relativeEnergy = energyMode === "since-open" && unitDatasets.some(dataset => Live.isEnergy(dataset.metaInfo));
			scales["unit-" + (unit || "value")] = {
				type: "linear", position: index === 0 ? "left" : "right", beginAtZero: power || relativeEnergy,
				grace: power || relativeEnergy ? 0 : "5%",
				title: { display: true, text: unit || i18n.value }, grid: { drawOnChartArea: index === 0 },
				ticks: { callback: value => formatNumber(value) + (unit ? " " + unit : "") }
			};
		});
		const config = {
			type: "line", data: { datasets }, options: {
				responsive: true, maintainAspectRatio: false, animation: false, normalized: true, parsing: false,
				interaction: { mode: "index", intersect: false }, scales,
				plugins: {
					decimation: { enabled: true, algorithm: "min-max" },
					legend: { position: "bottom", labels: { usePointStyle: true } },
					tooltip: { callbacks: { label: context => {
						const dataset = context.dataset, unit = dataset.metaInfo.unit || "", point = dataset.data[context.dataIndex];
						let text = dataset.label + ": " + formatNumber(context.parsed.y) + (unit ? " " + unit : "");
						if (energyMode === "since-open" && Live.isEnergy(dataset.metaInfo) && point && Number.isFinite(point.absolute)) text += " (" + i18n.absolute + ": " + formatNumber(point.absolute) + (unit ? " " + unit : "") + ")";
						return text;
					} } }
				}
			}
		};
		if (chart) {
			chart.data.datasets = datasets;
			datasets.forEach((dataset, index) => { if (visibility.has(dataset.uuid)) chart.setDatasetVisibility(index, visibility.get(dataset.uuid)); });
			chart.options.scales = scales;
			chart.update("none");
		} else chart = new Chart(document.getElementById("live-chart"), config);
		renderSummary();
	}

	function colorWithAlpha(hex, alpha) {
		const value = hex.replace("#", "");
		return "rgba(" + parseInt(value.slice(0,2),16) + "," + parseInt(value.slice(2,4),16) + "," + parseInt(value.slice(4,6),16) + "," + alpha + ")";
	}

	function latestPoint(uuid) { return Live.latestReading(histories.get(uuid) || []); }
	function firstPointSince(uuid, timestamp) { return (histories.get(uuid) || []).find(point => point.y !== null && point.x >= timestamp) || null; }

	function renderSummary() {
		const rangeStart = Date.now() - historyRange;
		const groups = new Map();
		channels.forEach(item => { const serial = String(item.meta.serial || "unknown"); if (!groups.has(serial)) groups.set(serial, []); groups.get(serial).push(item); });
		const output = [];
		groups.forEach((items, serial) => {
			if (!items.some(item => Live.isEnergy(item.meta) || Live.isPower(item.meta))) return;
			const imported = Live.chooseEnergyChannel(items, "import"), exported = Live.chooseEnergyChannel(items, "export");
			const segments = energySegments.get(serial) || [];
			const resetsInRange = segments.filter(segment => segment.reset && segment.start >= rangeStart);
			const latestSegment = resetsInRange.length ? resetsInRange[resetsInRange.length - 1] : null;
			const start = latestSegment ? latestSegment.start : rangeStart;
			function delta(item) { if (!item) return null; const first = firstPointSince(item.uuid, start), last = latestPoint(item.uuid); return first && last ? Math.max(0, last.absolute - first.absolute) : null; }
			const importDelta = delta(imported), exportDelta = delta(exported);
			const powerItems = Live.choosePowerChannels(items), powerValues = [];
			powerItems.forEach(item => (histories.get(item.uuid) || []).forEach(point => { if (point.y !== null && point.x >= rangeStart) powerValues.push({ value: Live.chartValue(point.y, item.meta), x: point.x }); }));
			const latestPowers = powerItems.map(item => ({ item, point: latestPoint(item.uuid) })).filter(entry => entry.point);
			let currentPower = null;
			if (latestPowers.length === 1 && Live.category(latestPowers[0].item.meta) === "active_power_total") currentPower = latestPowers[0].point.y;
			else if (latestPowers.length) currentPower = latestPowers.reduce((sum, entry) => sum + Live.chartValue(entry.point.y, entry.item.meta), 0);
			const { importPeak, exportPeak } = Live.powerPeaks(powerValues);
			const unit = imported && imported.meta.unit || exported && exported.meta.unit || "kWh";
			const balance = Number.isFinite(importDelta) && Number.isFinite(exportDelta) ? importDelta - exportDelta : NaN;
			const balanceSentence = Live.balanceText(balance, 0.001, { unavailable:i18n.unavailable, balanced:i18n.balanceEqual, moreImport:i18n.balanceImport, moreExport:i18n.balanceExport }, value => formatNumber(value, 3) + " " + unit);
			output.push('<section class="summary-reader"><h3>' + esc(items[0].meta.head_name || serial) + (latestSegment ? ' <small>' + esc(i18n.sinceRebaseline) + "</small>" : "") + '</h3><div class="summary-grid">');
			output.push(summaryCard(i18n.sessionImport, importDelta, unit));
			output.push(summaryCard(i18n.sessionExport, exportDelta, unit));
			output.push('<div class="summary-card"><span>' + esc(i18n.sessionBalance) + '</span><strong>' + esc(balanceSentence) + "</strong></div>");
			const direction = currentPower === null ? i18n.unavailable : (Math.abs(currentPower) < 0.001 ? i18n.balanceEqual : (currentPower > 0 ? i18n.currentImport : i18n.currentExport).replace("{value}", formatNumber(Math.abs(currentPower), 1) + " W"));
			output.push('<div class="summary-card"><span>' + esc(i18n.currentFlow) + '</span><strong>' + esc(direction) + "</strong></div>");
			output.push(peakCard(i18n.peakImport, importPeak)); output.push(peakCard(i18n.peakExport, exportPeak));
			output.push("</div></section>");
		});
		document.getElementById("session-summary").innerHTML = output.join("");
	}

	function summaryCard(label, value, unit) { return '<div class="summary-card"><span>' + esc(label) + '</span><strong>' + (Number.isFinite(value) ? esc(formatNumber(value, 6) + " " + unit) : esc(i18n.unavailable)) + "</strong></div>"; }
	function peakCard(label, peak) { return '<div class="summary-card"><span>' + esc(label) + '</span><strong>' + (peak ? esc(formatNumber(Math.abs(peak.value), 1) + " W") + '<small>' + esc(new Date(peak.x).toLocaleTimeString(locale)) + "</small>" : esc(i18n.unavailable)) + "</strong></div>"; }

	async function requestLiveData(checkMetadata) {
		const response = await fetch("vzlogger_live_data.cgi?" + languageQuery.substring(1), { cache: "no-store" });
		if (!response.ok) throw new Error(i18n.dataFailed);
		const version = response.headers.get("X-Smartmeter-Metadata-Version") || "";
		let metadataChanged = false;
		if (checkMetadata !== false && version && version !== metadataVersion) { await loadMetadata(); metadataChanged = true; }
		const data = await response.json();
		if (data && data.error_code) throw new Error(i18n.dataFailed);
		if (data && data.error) throw new Error(data.error);
		return { data, metadataChanged, version };
	}

	function showSuccessfulUpdate() {
		document.getElementById("status").className = "status";
		document.getElementById("status").textContent = i18n.lastUpdate + ": " + new Date().toLocaleString(locale);
	}

	function showRefreshError(error) {
		document.getElementById("status").className = "status error";
		document.getElementById("status").innerHTML = diagnosticHtml(error.message, error.message === i18n.dataFailed ? i18n.dataFailedHint : "");
	}

	async function refresh() {
		if (stopped || refreshing) return;
		refreshing = true;
		try {
			const { data, metadataChanged } = await requestLiveData(true);
			pollFailures = 0;
			const firstRender = currentData === null;
			const signature = Live.liveDataSignature(data);
			const responseChanged = signature !== lastLiveDataSignature;
			currentData = data;
			const historyChanged = ingest(data);
			lastLiveDataSignature = signature;
			if (!document.hidden) {
				if (firstRender || metadataChanged || responseChanged || historyChanged) { renderTable(data); updateChart(); }
				showSuccessfulUpdate();
			}
		} catch (error) {
			pollFailures++;
			if (!document.hidden) showRefreshError(error);
		} finally { refreshing = false; schedule(); }
	}

	function schedule(immediate) {
		clearTimeout(timer);
		if (stopped || !historyInitialized || (document.hidden && !backgroundCollection)) return;
		timer = setTimeout(refresh, immediate ? 0 : Live.pollDelay(pollFailures, pollInterval));
	}

	document.addEventListener("visibilitychange", () => {
		if (document.hidden) flushHistoryWrites();
		if (document.hidden && !backgroundCollection) { clearTimeout(timer); return; }
		if (!document.hidden && currentData) { renderTable(currentData); if (historyInitialized) updateChart(); }
		schedule(true);
	});
	document.getElementById("energy-mode").addEventListener("change", event => { energyMode = event.target.value === "absolute" ? "absolute" : "since-open"; savePreferences(); updateChart(); });
	document.getElementById("history-range").addEventListener("change", event => { const value = Number(event.target.value); historyRange = Live.RANGE_VALUES.includes(value) ? value : Live.DEFAULT_RANGE; historyRangeExplicit = true; savePreferences(); updateChart(); });
	document.getElementById("poll-interval").addEventListener("change", event => { const value = Number(event.target.value); pollInterval = Live.POLL_INTERVAL_VALUES.includes(value) ? value : Live.POLL_INTERVAL; savePreferences(); schedule(true); });
	document.getElementById("background-collection").addEventListener("change", event => { backgroundCollection = event.target.checked; savePreferences(); schedule(true); });
	document.getElementById("reset-chart-defaults").addEventListener("click", resetDefaults);
	document.getElementById("clear-history").addEventListener("click", () => document.getElementById("clear-history-dialog").showModal());
	document.getElementById("confirm-clear-history").addEventListener("click", async () => {
		try { await clearPersistedHistory(); showHistoryStorageMessage(i18n.historyCleared, false); }
		catch (_) { showHistoryStorageMessage(i18n.historyUnavailable, true); }
	});
	window.addEventListener("pagehide", flushHistoryWrites);
	window.addEventListener("beforeunload", () => { stopped = true; clearTimeout(timer); flushHistoryWrites(); });

	initializeCollapsiblePersistence();
	(async function initialize() {
		try {
			await loadMetadata();
			const historyInitialization = initializeHistoryStorage();
			let initialVersion = "";
			try {
				const initial = await requestLiveData(false);
				currentData = initial.data;
				initialVersion = initial.version;
				lastLiveDataSignature = Live.liveDataSignature(initial.data);
				pollFailures = 0;
				if (!document.hidden) { renderTable(initial.data); showSuccessfulUpdate(); }
			} catch (error) {
				pollFailures++;
				if (!document.hidden) showRefreshError(error);
			}
			await historyInitialization;
			if (initialVersion && initialVersion !== metadataVersion) await loadMetadata();
			historyInitialized = true;
			selectInitialHistoryRange();
			if (currentData) ingest(currentData);
			if (!document.hidden) updateChart();
			schedule(true);
		}
		catch (error) { document.getElementById("status").className = "status error"; document.getElementById("status").textContent = error.message; }
	}());
}());
