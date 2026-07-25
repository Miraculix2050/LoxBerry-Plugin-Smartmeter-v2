(function (global) {
	"use strict";

	function toggleElement(toggleOrId) {
		return typeof toggleOrId === "string" ? document.getElementById(toggleOrId) : toggleOrId;
	}

	function valueElement(toggle) {
		return document.getElementById(toggle.id + "_value");
	}

	function toggleValue(toggleOrId) {
		var toggle = toggleElement(toggleOrId);
		if (!toggle) return "";
		return toggle.checked ? toggle.dataset.onValue : toggle.dataset.offValue;
	}

	function setToggleValue(toggleOrId, value, notify) {
		var toggle = toggleElement(toggleOrId);
		if (!toggle) return;
		toggle.checked = String(value) === String(toggle.dataset.onValue);
		syncToggle(toggle);
		if (notify) toggle.dispatchEvent(new Event("change", { bubbles: true }));
	}

	function syncToggle(toggleOrId) {
		var toggle = toggleElement(toggleOrId);
		if (!toggle) return;
		var hidden = valueElement(toggle);
		if (hidden) hidden.value = toggleValue(toggle);
		toggle.setAttribute("aria-checked", toggle.checked ? "true" : "false");
	}

	function setToggleDisabled(toggleOrId, disabled) {
		var toggle = toggleElement(toggleOrId);
		if (!toggle) return;
		toggle.disabled = !!disabled;
		var wrapper = toggle.closest(".lb-toggle");
		if (wrapper) wrapper.setAttribute("aria-disabled", disabled ? "true" : "false");
	}

	function initializeToggles(root) {
		(root || document).querySelectorAll(".smartmeter-toggle-input").forEach(function (toggle) {
			var hidden = valueElement(toggle);
			if (hidden) setToggleValue(toggle, hidden.value, false);
			toggle.addEventListener("change", function () { syncToggle(toggle); });
		});
	}

	function initializeDesign(root) {
		var scope = root || document;
		scope.querySelectorAll("button").forEach(function (element) { element.classList.add("lb-btn"); });
		scope.querySelectorAll(
			"#btnrescan, #btnfetch, #btnshowlog, #btncancel, #rescan_ir_heads, " +
			"#show_generated_config, #http_cache_link, #vzlogger_live_link, #vzlogger_rendered_link, " +
			".service-action-line > a, .service-control-log > a"
		).forEach(function (element) { element.classList.add("lb-btn"); });
		scope.querySelectorAll("input:not([type='hidden']):not([type='checkbox']):not([type='radio'])").forEach(function (element) { element.classList.add("lb-input"); });
		scope.querySelectorAll("select").forEach(function (element) { element.classList.add("lb-select"); });
		scope.querySelectorAll("textarea:not([hidden])").forEach(function (element) { element.classList.add("lb-textarea"); });
		scope.querySelectorAll("table").forEach(function (element) { element.classList.add("lb-table"); });
		scope.querySelectorAll("form > table > tbody > tr, form .settings-table > tbody > tr, form .service-panel table > tbody > tr").forEach(function (row) {
			var cells = Array.prototype.filter.call(row.children, function (child) { return child.tagName === "TD"; });
			if (!cells.length || (cells.length === 1 && cells[0].hasAttribute("colspan"))) return;
			row.classList.add("smartmeter-form-row");
			if (cells[0]) cells[0].classList.add("lb-form-label");
			if (cells[1]) cells[1].classList.add("lb-form-field");
			if (cells[cells.length - 1] && cells.length > 2) cells[cells.length - 1].classList.add("lb-form-help");
		});
		["save_apply_button", "btnsubmit"].forEach(function (id) {
			var element = document.getElementById(id);
			if (element) element.classList.add("lb-btn-primary");
		});
		var icons = {
			vzlogger_restart_button: "pi-refresh", bridge_restart_button: "pi-refresh",
			vzlogger_start_button: "pi-play", bridge_start_button: "pi-play",
			vzlogger_stop_button: "pi-stop", bridge_stop_button: "pi-stop",
			validate_config_button: "pi-check-circle", debug_log_button: "pi-file",
			save_apply_button: "pi-save", btnsubmit: "pi-save", btncancel: "pi-times",
			btnrescan: "pi-refresh", btnfetch: "pi-play", btnshowlog: "pi-list",
			btnlog: "pi-trash", reset_expert_config: "pi-refresh",
			rescan_ir_heads: "pi-search", show_generated_config: "pi-search",
			http_cache_link: "pi-external-link", vzlogger_live_link: "pi-external-link",
			vzlogger_rendered_link: "pi-chart-line",
			ir_scan_close: "pi-times", obis_search_cancel: "pi-times",
			service_action_hide: "pi-eye-slash", service_action_close: "pi-times",
			configuration_action_close: "pi-times"
		};
		Object.keys(icons).forEach(function (id) {
			var element = scope.querySelector("#" + id);
			if (!element || element.querySelector(":scope > .pi")) return;
			var icon = document.createElement("i");
			icon.className = "pi " + icons[id];
			icon.setAttribute("aria-hidden", "true");
			element.insertBefore(icon, element.firstChild);
		});
	}

	function setLinkDisabled(linkOrSelector, disabled) {
		var links = typeof linkOrSelector === "string"
			? document.querySelectorAll(linkOrSelector)
			: (linkOrSelector instanceof Element ? [linkOrSelector] : linkOrSelector);
		Array.prototype.forEach.call(links || [], function (link) {
			link.classList.toggle("is-disabled", !!disabled);
			link.setAttribute("aria-disabled", disabled ? "true" : "false");
			if (disabled) link.setAttribute("tabindex", "-1");
			else link.removeAttribute("tabindex");
		});
	}

	global.smartmeterToggleValue = toggleValue;
	global.smartmeterSetToggleValue = setToggleValue;
	global.smartmeterSyncToggle = syncToggle;
	global.smartmeterSetToggleDisabled = setToggleDisabled;
	global.smartmeterInitializeToggles = initializeToggles;
	global.smartmeterInitializeDesign = initializeDesign;
	global.smartmeterSetLinkDisabled = setLinkDisabled;

	if (document.readyState === "loading") {
		document.addEventListener("DOMContentLoaded", function () {
			initializeToggles(document);
			initializeDesign(document);
		});
	} else {
		initializeToggles(document);
		initializeDesign(document);
	}
})(window);
