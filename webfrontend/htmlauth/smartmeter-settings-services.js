(function (root, factory) {
	var api = factory();
	if (typeof module === "object" && module.exports) module.exports = api;
	else root.SmartMeterSettingsServices = api;
}(typeof globalThis !== "undefined" ? globalThis : this, function () {
	"use strict";
	function statusUrl(detailed, language, now) {
		return "./service_status.cgi?details=" + (detailed ? "1" : "0") + "&lang=" + encodeURIComponent(language) + "&_=" + (now == null ? Date.now() : now);
	}
	function mergeSnapshot(previous, response, expertMode, expertState) {
		var snapshot = previous || {};
		var state = {
			expert_runtime_applied: !!(expertState && expertState.expert_runtime_applied),
			expert_mqtt_enabled: !!(expertState && expertState.expert_mqtt_enabled),
			expert_mqtt_timestamp: !!(expertState && expertState.expert_mqtt_timestamp)
		};
		if (!response || !response.services) return { snapshot: snapshot, expert: state };
		snapshot.ok = response.ok;
		snapshot.services = response.services;
		if (response.applied) snapshot.applied = response.applied;
		if (response.config) {
			snapshot.config = response.config;
			state.expert_runtime_applied = !!response.config.expert_applied;
			if (expertMode) {
				if (Object.prototype.hasOwnProperty.call(response.config, "mqtt_enabled")) state.expert_mqtt_enabled = !!response.config.mqtt_enabled;
				if (Object.prototype.hasOwnProperty.call(response.config, "mqtt_timestamp")) state.expert_mqtt_timestamp = !!response.config.mqtt_timestamp;
			}
		}
		return { snapshot: snapshot, expert: state };
	}
	return { statusUrl: statusUrl, mergeSnapshot: mergeSnapshot };
}));
