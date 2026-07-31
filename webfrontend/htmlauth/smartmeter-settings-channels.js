(function (root, factory) {
	var api = factory();
	if (typeof module === "object" && module.exports) module.exports = api;
	else root.SmartMeterSettingsChannels = api;
}(typeof globalThis !== "undefined" ? globalThis : this, function () {
	"use strict";
	function readDocument(value, fallback) {
		try { var parsed = JSON.parse(value || "{}"); return parsed && typeof parsed === "object" ? parsed : fallback; }
		catch (error) { return fallback; }
	}
	function normalizeDocument(document) {
		document = document && typeof document === "object" ? document : {};
		if (!document.version) document.version = 1;
		if (!document.meters || typeof document.meters !== "object") document.meters = {};
		return document;
	}
	function existingOutputKeys(document, serial) {
		return ((document.meters || {})[serial] || []).map(function (channel) { return (channel.plugin_output || {}).key || ""; }).filter(Boolean);
	}
	return { readDocument: readDocument, normalizeDocument: normalizeDocument, existingOutputKeys: existingOutputKeys };
}));
