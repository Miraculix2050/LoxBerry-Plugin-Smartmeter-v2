"use strict";

const assert = require("assert");
const Services = require("../webfrontend/htmlauth/smartmeter-settings-services.js");
const Discovery = require("../webfrontend/htmlauth/smartmeter-settings-discovery.js");
const Channels = require("../webfrontend/htmlauth/smartmeter-settings-channels.js");

const previous = { services: { vzlogger: { running: true } }, config: { mqtt_timestamp: true } };
const expert = { expert_runtime_applied: true, expert_mqtt_enabled: true, expert_mqtt_timestamp: true };
const actionResponseWithoutTimestamp = {
	ok: true,
	services: { vzlogger: { running: true }, bridge: { running: false } },
	config: { expert_applied: true, mqtt_enabled: true }
};
const merged = Services.mergeSnapshot(previous, actionResponseWithoutTimestamp, true, expert);
assert.strictEqual(merged.expert.expert_mqtt_timestamp, true, "missing optional timestamp keeps the previous Expert state");
assert.strictEqual(merged.expert.expert_mqtt_enabled, true);
assert.strictEqual(merged.snapshot.services.bridge.running, false);

const explicitFalse = Services.mergeSnapshot(merged.snapshot, {
	ok: true, services: actionResponseWithoutTimestamp.services,
	config: { expert_applied: true, mqtt_enabled: true, mqtt_timestamp: false }
}, true, merged.expert);
assert.strictEqual(explicitFalse.expert.expert_mqtt_timestamp, false, "explicit false updates the Expert state");
assert.strictEqual(Services.statusUrl(true, "de", 10), "./service_status.cgi?details=1&lang=de&_=10");

assert.strictEqual(Discovery.activeState("running"), true);
assert.strictEqual(Discovery.activeState("completed"), false);
assert.strictEqual(Discovery.pollDelay(20), 10000, "discovery retry delay is bounded");
assert.strictEqual(Discovery.ajaxUrl("obis-status", "en", 20), "./obis_status.cgi?lang=en&_=20");

const document = Channels.normalizeDocument(Channels.readDocument('{"meters":{"r":[{"plugin_output":{"key":"Energy"}}]}}', {}));
assert.strictEqual(document.version, 1);
assert.deepStrictEqual(Channels.existingOutputKeys(document, "r"), ["Energy"]);
assert.deepStrictEqual(Channels.normalizeDocument(Channels.readDocument("invalid", {})).meters, {});

console.log("settings module tests passed");
