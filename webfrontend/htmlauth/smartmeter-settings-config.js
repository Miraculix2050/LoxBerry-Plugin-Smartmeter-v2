(function (root, factory) {
	var api = factory();
	if (typeof module === "object" && module.exports) module.exports = api;
	else root.SmartMeterSettingsConfig = api;
}(typeof globalThis !== "undefined" ? globalThis : this, function () {
	"use strict";
	function actionOutcome(action, response, error, fallback) {
		if (error) return { action: action, ok: false, result: "failed", message: (fallback || "Request failed") + ": " + (error.message || error) };
		response = response || {};
		return {
			action: action,
			ok: !!response.ok,
			result: !response.ok ? "failed" : (response.warning ? "warning" : "success"),
			message: response.message || (response.ok ? "OK" : (fallback || "Request failed"))
		};
	}
	function setBusy(form, busy) {
		if (!form) return false;
		if (busy) form.setAttribute("aria-busy", "true");
		else form.removeAttribute("aria-busy");
		return true;
	}
	return { actionOutcome: actionOutcome, setBusy: setBusy };
}));
