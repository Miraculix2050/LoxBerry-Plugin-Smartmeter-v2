(function (root, factory) {
	var api = factory();
	if (typeof module === "object" && module.exports) module.exports = api;
	else root.SmartMeterChannelModel = api;
}(typeof globalThis !== "undefined" ? globalThis : this, function () {
	"use strict";

	function parseObis(value) {
		var match = String(value || "").trim().match(/^(?:(\d+)-(\d+):)?([A-Za-z0-9]+)\.(\d+)\.(\d+)(?:\*(\d+))?$/);
		if (!match) return null;
		var storage = match[6] == null || match[6] === "255" ? null : Number(match[6]);
		if (storage != null && (storage < 0 || storage > 254)) return null;
		return {
			a: match[1] == null ? null : Number(match[1]),
			b: match[2] == null ? null : Number(match[2]),
			c: /^\d+$/.test(match[3]) ? Number(match[3]) : match[3],
			d: Number(match[4]), e: Number(match[5]), f: storage,
			base: (match[1] == null ? "" : match[1] + "-" + match[2] + ":") + match[3] + "." + match[4] + "." + match[5]
		};
	}

	function fullObis(channel) {
		return channel.obis + (channel.storage == null || channel.storage === "" || String(channel.storage) === "255" ? "" : "*" + channel.storage);
	}

	function catalogInfo(identifier, catalog, language, unknown) {
		var parsed = parseObis(identifier);
		unknown = unknown || "Unknown";
		if (!parsed) return { short: unknown, long: unknown, unit: "", recommended_aggmode: "none", output_name: "Unknown" };
		var full = parsed.base + (parsed.f == null ? "" : "*" + parsed.f);
		var entries = catalog && catalog.entries || [];
		var rules = catalog && catalog.rules || [];
		var entry = entries.find(function (item) { return item.code === full; }) || entries.find(function (item) { return item.code === parsed.base; });
		if (!entry) entry = rules.slice().sort(function (a, b) { return (a.priority || 9999) - (b.priority || 9999); }).find(function (item) {
			return Object.keys(item.match || {}).every(function (group) {
				var wanted = item.match[group], actual = parsed[group];
				return Array.isArray(wanted) ? wanted.map(String).indexOf(String(actual)) >= 0 : String(wanted) === String(actual);
			});
		});
		var lang = language === "de" ? "de" : "en";
		var groups = (lang === "de" ? " Gruppen A (Medium)=" : " Groups A (medium)=") +
			(parsed.a == null ? (lang === "de" ? "nicht angegeben" : "not specified") : parsed.a) + ", B (" +
			(lang === "de" ? "Kanal" : "channel") + ")=" + (parsed.b == null ? (lang === "de" ? "nicht angegeben" : "not specified") : parsed.b) +
			", C (" + (lang === "de" ? "Messgröße" : "quantity") + ")=" + parsed.c + ", D (" +
			(lang === "de" ? "Verarbeitung" : "processing") + ")=" + parsed.d + ", E (" +
			(lang === "de" ? "Tarif/Ausprägung" : "tariff/variant") + ")=" + parsed.e + ", F (" +
			(lang === "de" ? "Speicher" : "storage") + ")=" + (parsed.f == null ? (lang === "de" ? "nicht angegeben" : "not specified") : parsed.f) + ".";
		if (!entry) return { short: unknown, long: unknown + groups, unit: "", recommended_aggmode: "none", output_name: "Unknown" };
		return {
			short: (entry.short || {})[lang] || (entry.short || {}).en || parsed.base,
			long: ((entry.long || {})[lang] || (entry.long || {}).en || "") + groups,
			unit: entry.unit || "", recommended_aggmode: entry.recommended_aggmode || "none",
			warning: (entry.limitations || {})[lang] || "",
			output_name: entry.output_name || (entry.short || {}).en || ""
		};
	}

	function defaultOutputKey(parsed, info) {
		var name = String(info && (info.output_name || info.short) || "Unknown").replace(/\s+/g, "_").replace(/[^A-Za-z0-9_]+/g, "_").replace(/^_+|_+$/g, "") || "Value";
		var shortObis = parsed.c + "." + parsed.d + "." + parsed.e + (parsed.f == null ? "" : "*" + parsed.f);
		var suffix = "_OBIS_" + shortObis, available = 64 - suffix.length;
		if (available < 1) return ("Value" + suffix).substring(0, 64);
		if (name.length > available) name = name.substring(0, available).replace(/_+$/g, "");
		return name + suffix;
	}

	function uniqueOutputKey(key, existing) {
		var used = {};
		(existing || []).forEach(function (value) { if (value) used[String(value).toLowerCase()] = true; });
		var candidate = key, number = 2;
		while (used[candidate.toLowerCase()]) {
			var suffix = "_" + number++;
			candidate = key.substring(0, 64 - suffix.length) + suffix;
		}
		return candidate;
	}

	function validOutputKey(key) {
		return typeof key === "string" && /^[A-Za-z0-9 _#|()\[\]\/\'%$!.*-]{1,64}$/.test(key);
	}

	return { parseObis: parseObis, fullObis: fullObis, catalogInfo: catalogInfo, defaultOutputKey: defaultOutputKey, uniqueOutputKey: uniqueOutputKey, validOutputKey: validOutputKey };
}));
