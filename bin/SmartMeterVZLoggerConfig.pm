package SmartMeterVZLoggerConfig;

use strict;
use warnings;
use Exporter qw(import);
use JSON::PP;

our @EXPORT_OK = qw(read_mqtt_settings read_webserver_settings clean_boolean clean_number clean_qos sanitize_topic protocol_for_meter normalized_meter_mode vzlogger_enabled set_vzlogger_enabled);

sub clean_boolean
{
	my ($value, $fallback) = @_;
	return $fallback ? 1 : 0 if (!defined($value) || ref($value));
	return $value ? 1 : 0 if ($value =~ /\A(?:0|1)\z/);
	return $fallback ? 1 : 0;
}

sub vzlogger_enabled
{
	my ($plugin_cfg) = @_;
	return 0 if (!$plugin_cfg);
	return clean_boolean($plugin_cfg->param("VZLOGGER.ENABLED"), 0);
}

sub set_vzlogger_enabled
{
	my ($plugin_cfg, $enabled) = @_;
	die "Invalid vzLogger activation state.\n" if (!$plugin_cfg || !defined($enabled) || $enabled !~ /\A[01]\z/);
	$plugin_cfg->param("VZLOGGER.ENABLED", $enabled);
	return int($enabled);
}

sub protocol_for_meter
{
	my ($meter) = @_;
	return "" if (!defined($meter));
	return "sml" if ($meter =~ /sml\z/i);
	return "d0" if ($meter =~ /(?:d0|do)\z/i);
	return "oms" if ($meter =~ /oms\z/i);
	return "";
}

sub normalized_meter_mode
{
	my ($meter, $manual_protocol) = @_;
	$meter ||= "0";
	return $meter if ($meter =~ /\A(?:0|sml|d0|oms|user)\z/);
	return protocol_for_meter($manual_protocol) || "user" if ($meter eq "manual");
	return protocol_for_meter($meter) || "user";
}

sub read_mqtt_settings
{
	my ($home, $plugin_cfg) = @_;
	my %settings = (host => "127.0.0.1", port => 1883, user => "", pass => "", cafile => "", capath => "", certfile => "", keyfile => "", keypass => "");
	my $general_json = "$home/config/system/general.json";
	if (-e $general_json && open(my $fh, "<", $general_json)) {
		local $/;
		my $general = eval { JSON::PP->new->utf8->decode(<$fh> || "") };
		close($fh);
		if (!$@ && ref($general) eq "HASH" && ref($general->{Mqtt}) eq "HASH") {
			my $mqtt = $general->{Mqtt};
			$settings{host} = _first_value($mqtt, qw(Host Hostname Broker Brokerhost Server IpAddress Ipaddress)) || $settings{host};
			$settings{port} = clean_number(_first_value($mqtt, qw(Port Brokerport Mqttport)), $settings{port});
			$settings{user} = _first_value($mqtt, qw(Brokeruser Brokerusername User Username Login)) || "";
			$settings{pass} = _first_value($mqtt, qw(Brokerpass Brokerpassword Pass Password)) || "";
		}
	}
	if ($plugin_cfg) {
		my %keys = (host=>"MQTTHOST",port=>"MQTTPORT",cafile=>"MQTTCAFILE",capath=>"MQTTCAPATH",certfile=>"MQTTCERTFILE",keyfile=>"MQTTKEYFILE",keypass=>"MQTTKEYPASS",user=>"MQTTUSER",pass=>"MQTTPASS");
		foreach my $key (keys %keys) {
			my $value = $plugin_cfg->param("VZLOGGER.$keys{$key}");
			next if (!defined($value) || ref($value) || $value eq "");
			$value =~ s/[\r\n]//g if ($key ne "port");
			$settings{$key} = $key eq "port" ? clean_number($value, $settings{$key}) : "$value";
		}
	}
	return \%settings;
}

sub read_webserver_settings
{
	my ($general_json) = @_;
	my %settings = (http_port => 80, https_enabled => 0, https_port => 443);
	return \%settings if (!-e $general_json || !open(my $fh, "<", $general_json));
	local $/;
	my $general = eval { JSON::PP->new->utf8->decode(<$fh> || "") };
	close($fh);
	return \%settings if ($@ || ref($general) ne "HASH" || ref($general->{Webserver}) ne "HASH");

	my $webserver = $general->{Webserver};
	$settings{http_port} = _valid_port($webserver->{Port}, 80);
	$settings{https_port} = _valid_port($webserver->{Sslport}, 443);
	$settings{https_enabled} = _enabled_value($webserver->{Sslenabled});
	return \%settings;
}

sub _valid_port
{
	my ($value, $default) = @_;
	return $default if (!defined($value) || ref($value) || $value !~ /\A\d+\z/ || $value < 1 || $value > 65535);
	return int($value);
}

sub _enabled_value
{
	my ($value) = @_;
	return 0 if (!defined($value) || ref($value));
	return $value =~ /\A(?:1|true|yes|on|enabled)\z/i ? 1 : 0;
}

sub _first_value
{
	my ($hash, @keys) = @_;
	foreach my $key (@keys) { return $hash->{$key} if (defined($hash->{$key}) && $hash->{$key} ne ""); }
	return undef;
}

sub clean_number
{
	my ($value, $default) = @_;
	return int($value) if (defined($value) && !ref($value) && $value =~ /\A\d+\z/);
	return $default;
}

sub clean_qos
{
	my ($value, $default) = @_;
	$default = 0 if (!defined($default) || ref($default) || $default !~ /\A[01]\z/);
	return defined($value) && !ref($value) && $value =~ /\A[01]\z/ ? int($value) : int($default);
}

sub sanitize_topic
{
	my ($topic) = @_;
	$topic ||= "smartmeter";
	$topic =~ s/^\s+|\s+$//g;
	$topic =~ s{^/+|/+$}{}g;
	$topic =~ s/[#+]//g;
	return $topic || "smartmeter";
}

1;
