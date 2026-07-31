package SmartMeterVZLoggerServicePolicy;

use strict;
use warnings;
use Exporter qw(import);

our @EXPORT_OK = qw(manual_start_decision recovery_decision bridge_expected);

sub bridge_expected
{
	my (%state) = @_;
	return 0 if (!$state{vzlogger_enabled} || !$state{bridge_enabled});
	return 0 if (!$state{mqtt_output} && !$state{http_cache} && !$state{udp_output});
	return $state{mqtt_enabled} ? 1 : 0;
}

sub manual_start_decision
{
	my (%state) = @_;
	if (!$state{desired}) {
		return { allowed => 0, exit_code => 0, reason => $state{service} eq "bridge" ? "bridge_disabled" : "vzlogger_disabled" };
	}
	if ($state{service} eq "vzlogger" && ($state{active_meters} || 0) <= 0) {
		return { allowed => 0, exit_code => 1, reason => "no_active_meter" };
	}
	if ($state{service} eq "bridge" && !$state{generated_mqtt}) {
		return { allowed => 0, exit_code => 1, reason => "mqtt_disabled" };
	}
	if ($state{service} eq "bridge" && $state{bridge_mqtt} && !$state{generated_timestamp}) {
		return { allowed => 0, exit_code => 1, reason => "timestamp_required" };
	}
	return { allowed => 1, exit_code => 0, reason => "allowed" };
}

sub recovery_decision
{
	my (%state) = @_;
	return { action => "skip", reason => "not_configured" } if (!$state{expected});
	return { action => "skip", reason => "not_installed" } if (($state{load_state} || "") ne "loaded");
	return { action => "skip", reason => "unit_disabled" }
		if (($state{unit_state} || "") ne "enabled" && ($state{unit_state} || "") ne "enabled-runtime");
	my $active = $state{active_state} || "unknown";
	return { action => "skip", reason => "manual_stop" } if ($active eq "inactive");
	return { action => "skip", reason => "busy" } if ($active =~ /\A(?:activating|deactivating|reloading)\z/);
	return { action => "skip", reason => "unsupported_state" } if ($active ne "active" && $active ne "failed");
	my $last = $state{last_recovery} || 0;
	my $now = $state{now} || 0;
	my $cooldown = $state{cooldown} || 300;
	if ($last =~ /\A\d+\z/ && $now - $last < $cooldown) {
		return { action => "skip", reason => "cooldown", retry_after => $cooldown - ($now - $last) };
	}
	return { action => "fail", reason => "invalid_configuration" } if (!$state{configuration_valid});
	return { action => "fail", reason => "mqtt_disabled" } if ($state{service} eq "bridge" && !$state{generated_mqtt});
	return { action => $active eq "failed" ? "start" : "restart", reason => "eligible" };
}

1;
