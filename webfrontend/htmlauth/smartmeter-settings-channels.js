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
	function mergeDiscovered(document, serial, discovered, createChannel, fullObis) {
		document = normalizeDocument(document);
		var channels = document.meters[serial] || (document.meters[serial] = []);
		var existing = {};
		channels.forEach(function (channel) { existing[fullObis(channel)] = true; });
		(discovered || []).forEach(function (item) {
			var identifier = item && item.identifier || "";
			if (!identifier || existing[identifier]) return;
			var channel = createChannel(identifier);
			if (!channel) return;
			channels.push(channel);
			existing[identifier] = true;
		});
		return channels;
	}
	function removeManual(document, serial, index) {
		var channels = document && document.meters && document.meters[serial];
		if (!Array.isArray(channels) || !channels[index] || channels[index].origin !== "manual") return null;
		return channels.splice(index, 1)[0];
	}
	function writeDocumentValue(element, document) {
		if (!element) return false;
		element.value = JSON.stringify(normalizeDocument(document));
		return true;
	}
	return { readDocument: readDocument, normalizeDocument: normalizeDocument, existingOutputKeys: existingOutputKeys, mergeDiscovered: mergeDiscovered, removeManual: removeManual, writeDocumentValue: writeDocumentValue };
}));
