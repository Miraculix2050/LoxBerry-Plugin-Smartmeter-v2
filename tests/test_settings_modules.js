"use strict";

const assert = require("assert");
const Services = require("../webfrontend/htmlauth/smartmeter-settings-services.js");
const Discovery = require("../webfrontend/htmlauth/smartmeter-settings-discovery.js");
const Channels = require("../webfrontend/htmlauth/smartmeter-settings-channels.js");
const Config = require("../webfrontend/htmlauth/smartmeter-settings-config.js");

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
assert.strictEqual(Services.pollAllowed({ hidden: false, serviceActionRunning: false, configurationActionRunning: false, inFlight: false }), true);
assert.strictEqual(Services.pollAllowed({ hidden: false, serviceActionRunning: true }), false);
assert.deepStrictEqual(Services.actionOutcome({ ok: true, warning: true, message: "warning" }), { ok: true, result: "warning", message: "warning", needsStatusRefresh: true });

assert.strictEqual(Discovery.activeState("running"), true);
assert.strictEqual(Discovery.activeState("completed"), false);
assert.strictEqual(Discovery.pollDelay(20), 10000, "discovery retry delay is bounded");
assert.strictEqual(Discovery.ajaxUrl("obis-status", "en", 20), "./obis_status.cgi?lang=en&_=20");
assert.deepStrictEqual(Discovery.statusTransition({ state: "cancelled" }), { terminal: true, result: "cancelled" });
assert.deepStrictEqual(Discovery.statusTransition({ state: "running" }), { terminal: false, result: "running", delay: 1000 });

const document = Channels.normalizeDocument(Channels.readDocument('{"meters":{"r":[{"plugin_output":{"key":"Energy"}}]}}', {}));
assert.strictEqual(document.version, 1);
assert.deepStrictEqual(Channels.existingOutputKeys(document, "r"), ["Energy"]);
assert.deepStrictEqual(Channels.normalizeDocument(Channels.readDocument("invalid", {})).meters, {});
const channelDocument = { version: 1, meters: { r: [{ origin: "manual", obis: "1-0:1.8.0", storage: null, plugin_output: { key: "Energy" } }] } };
Channels.mergeDiscovered(channelDocument, "r", [{ identifier: "1-0:1.8.0" }, { identifier: "1-0:2.8.0" }],
	(identifier) => ({ origin: "discovered", identifier, plugin_output: { key: "Delivery" } }),
	(channel) => channel.identifier || channel.obis);
assert.strictEqual(channelDocument.meters.r.length, 2, "discovery merge ignores existing identifiers");
assert.strictEqual(Channels.removeManual(channelDocument, "r", 0).origin, "manual");
assert.strictEqual(Channels.removeManual(channelDocument, "r", 0), null, "discovered channels cannot be removed as manual");
const hiddenDocument = { value: "" };
assert.strictEqual(Channels.writeDocumentValue(hiddenDocument, channelDocument), true);
assert.deepStrictEqual(JSON.parse(hiddenDocument.value), channelDocument, "hidden channel document receives the authoritative state");

assert.deepStrictEqual(Config.actionOutcome("apply", { ok: true, warning: false, message: "done" }), { action: "apply", ok: true, result: "success", message: "done" });
const fakeForm = {
	attributes: {},
	setAttribute(name, value) { this.attributes[name] = value; },
	removeAttribute(name) { delete this.attributes[name]; }
};
Config.setBusy(fakeForm, true);
assert.strictEqual(fakeForm.attributes["aria-busy"], "true");
Config.setBusy(fakeForm, false);
assert.strictEqual(fakeForm.attributes["aria-busy"], undefined, "busy state is removed after an action");

console.log("settings module tests passed");
