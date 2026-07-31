#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use Test::More;
use lib "$FindBin::Bin/../bin";
use SmartMeterVZLoggerServicePolicy qw(manual_start_decision recovery_decision bridge_expected);

is(manual_start_decision(service => "vzlogger", desired => 0, active_meters => 1)->{reason}, "vzlogger_disabled", "disabled vzLogger is not started");
is(manual_start_decision(service => "vzlogger", desired => 1, active_meters => 0)->{reason}, "no_active_meter", "meterless vzLogger is rejected");
ok(manual_start_decision(service => "vzlogger", desired => 1, active_meters => 1)->{allowed}, "configured vzLogger may start");
is(manual_start_decision(service => "bridge", desired => 1, generated_mqtt => 0)->{reason}, "mqtt_disabled", "bridge needs generated MQTT");
is(manual_start_decision(service => "bridge", desired => 1, generated_mqtt => 1, bridge_mqtt => 1, generated_timestamp => 0)->{reason}, "timestamp_required", "bridge MQTT needs source timestamps");
ok(manual_start_decision(service => "bridge", desired => 1, generated_mqtt => 1, bridge_mqtt => 0)->{allowed}, "cache-only bridge does not require source timestamps");

ok(bridge_expected(vzlogger_enabled => 1, bridge_enabled => 1, http_cache => 1, mqtt_enabled => 1), "enabled HTTP bridge is expected");
ok(!bridge_expected(vzlogger_enabled => 1, bridge_enabled => 1, mqtt_enabled => 1), "bridge without outputs is not expected");

my %eligible = (
	service => "vzlogger", expected => 1, load_state => "loaded", unit_state => "enabled",
	active_state => "active", last_recovery => 0, now => 1000, cooldown => 300,
	configuration_valid => 1, generated_mqtt => 1,
);
is_deeply(recovery_decision(%eligible), { action => "restart", reason => "eligible" }, "active expected service is restarted");
is(recovery_decision(%eligible, active_state => "failed")->{action}, "start", "failed expected service is reset and started");
is(recovery_decision(%eligible, active_state => "inactive")->{reason}, "manual_stop", "manual stop is preserved");
is(recovery_decision(%eligible, expected => 0)->{reason}, "not_configured", "disabled service is preserved");
is(recovery_decision(%eligible, unit_state => "disabled")->{reason}, "unit_disabled", "disabled unit is preserved");
is(recovery_decision(%eligible, last_recovery => 900)->{retry_after}, 200, "cooldown reports remaining time");
is(recovery_decision(%eligible, configuration_valid => 0)->{action}, "fail", "invalid generated configuration fails recovery");
is(recovery_decision(%eligible, service => "bridge", generated_mqtt => 0)->{reason}, "mqtt_disabled", "bridge recovery checks applied MQTT");

done_testing();
