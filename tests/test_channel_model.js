"use strict";

const assert = require("assert");
const fs = require("fs");
const path = require("path");
const Model = require("../webfrontend/htmlauth/smartmeter-channel-model.js");
const fixtures = JSON.parse(fs.readFileSync(path.join(__dirname, "fixtures", "channel-model.json"), "utf8"));

for (const item of fixtures.parse) {
	const parsed = Model.parseObis(item.input);
	if (item.normalized == null) {
		assert.strictEqual(parsed, null, `JavaScript rejects ${item.input}`);
	} else {
		assert.ok(parsed, `JavaScript parses ${item.input}`);
		assert.strictEqual(parsed.base + (parsed.f == null ? "" : `*${parsed.f}`), item.normalized);
		assert.strictEqual(parsed.f, item.storage);
	}
}
for (const item of fixtures.keys) {
	const parsed = Model.parseObis(item.identifier);
	assert.strictEqual(Model.defaultOutputKey(parsed, { output_name: item.name }), item.expected);
}
for (const key of fixtures.valid_keys) assert.strictEqual(Model.validOutputKey(key), true, `valid key ${key}`);
for (const key of fixtures.invalid_keys) assert.strictEqual(Model.validOutputKey(key), false, `invalid key ${key}`);
assert.strictEqual(Model.uniqueOutputKey("Value", ["value", "Value_2"]), "Value_3");
assert.strictEqual(Model.fullObis({ obis: "1-0:1.8.0", storage: 255 }), "1-0:1.8.0");

console.log("channel model tests passed");
