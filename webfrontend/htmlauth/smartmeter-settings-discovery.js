(function (root, factory) {
	var api = factory();
	if (typeof module === "object" && module.exports) module.exports = api;
	else root.SmartMeterSettingsDiscovery = api;
}(typeof globalThis !== "undefined" ? globalThis : this, function () {
	"use strict";
	function ajaxUrl(action, language, now) {
		if (action === "obis-status") return "./obis_status.cgi?lang=" + encodeURIComponent(language) + "&_=" + (now == null ? Date.now() : now);
		return "./index.cgi?ajax=1&ajaxaction=" + encodeURIComponent(action) + "&lang=" + encodeURIComponent(language) + "&_=" + (now == null ? Date.now() : now);
	}
	function activeState(state) { return /^(starting|running|cancelling)$/.test(String(state || "")); }
	function pollDelay(failures) { return Math.min(1000 * Math.pow(2, Math.max(0, failures || 0)), 10000); }
	function statusTransition(status) {
		status = status || {};
		if (status.state === "completed") return { terminal: true, result: "completed", channels: status.channels || [], warning: status.warning || "", restoreFailed: !!status.restore_failed };
		if (status.state === "cancelled") return { terminal: true, result: "cancelled" };
		if (status.state === "failed") return { terminal: true, result: "failed", message: status.message || "" };
		return { terminal: false, result: activeState(status.state) ? status.state : "waiting", delay: 1000 };
	}
	return { ajaxUrl: ajaxUrl, activeState: activeState, pollDelay: pollDelay, statusTransition: statusTransition };
}));
