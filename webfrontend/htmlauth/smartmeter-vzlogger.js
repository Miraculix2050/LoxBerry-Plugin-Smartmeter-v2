(function (global) {
	"use strict";
	const PREFIX = "smartmeter-vzlogger";
	function storageKey(kind, identity) { return PREFIX + "-" + kind + ":" + window.location.pathname + ":" + identity; }
	function readOpen(kind, identity, fallback) {
		try {
			const state = window.localStorage.getItem(storageKey(kind, identity));
			if (state === "open") return true;
			if (state === "closed") return false;
		} catch (_) { /* Browser storage is optional. */ }
		return !!fallback;
	}
	function writeOpen(kind, identity, open) {
		try { window.localStorage.setItem(storageKey(kind, identity), open ? "open" : "closed"); }
		catch (_) { /* Browser storage is optional. */ }
	}
	function initializeDeferredPanel(panel, initialize) {
		if (!panel || panel.open) return false;
		panel.dataset.deferredInitialization = "1";
		if (panel.dataset.deferredListener !== "1") {
			panel.dataset.deferredListener = "1";
			panel.addEventListener("toggle", function () {
				if (panel.open && panel.dataset.deferredInitialization === "1") initialize(panel);
			});
		}
		return true;
	}
	global.SmartMeterVZLoggerUi = { storageKey, readOpen, writeOpen, initializeDeferredPanel };
}(window));
