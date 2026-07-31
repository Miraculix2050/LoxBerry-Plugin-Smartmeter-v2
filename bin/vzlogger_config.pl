#!/usr/bin/perl

use strict;
use warnings;

use Config::Simple;
use File::Path qw(make_path);
use FindBin;
use JSON::PP;
use LoxBerry::System;
use lib $FindBin::Bin;
use SmartMeterVZLoggerChannelDocument qw(read_json write_json_atomic new_document initialize_channel_definitions validate_document native_channel);
use SmartMeterVZLoggerChannelSemantics qw(load_catalog lookup_obis normalize_obis);
use SmartMeterVZLoggerCustomChannels qw(assign_custom_channel_uuids);
use SmartMeterVZLoggerConfig qw(read_mqtt_settings clean_number clean_qos sanitize_topic protocol_for_meter normalized_meter_mode vzlogger_enabled);
use SmartMeterVZLoggerMeterInput qw(set_optional_text set_optional_integer set_optional_enum set_optional_boolean parse_meter_jsonc meter_jsonc_error_text safe_filename);
use SmartMeterVZLoggerDiscovery ();

my $home = $lbhomedir;
my $psubfolder = $lbpplugindir;
my $plugin_config_dir = $ENV{SMARTMETER_CONFIG_DIR} || $lbpconfigdir;
my $config_file = $ENV{SMARTMETER_CONFIG_FILE} || "$plugin_config_dir/smartmeter.cfg";
my $target_file = $ENV{SMARTMETER_VZLOGGER_CONFIG_FILE} || "$plugin_config_dir/vzlogger.conf";
my $mapping_file = $ENV{SMARTMETER_VZLOGGER_MAPPING_FILE} || "$plugin_config_dir/vzlogger_channels.json";
my $definitions_file = $ENV{SMARTMETER_VZLOGGER_DEFINITIONS_FILE} || "$plugin_config_dir/vzlogger_channel_definitions.json";
my $uuid_registry_dir = $ENV{SMARTMETER_UUID_REGISTRY_DIR} || $plugin_config_dir;
my $catalog_file = $ENV{SMARTMETER_OBIS_CATALOG_FILE} || "$lbptemplatedir/obis_catalog.json";
my $plugin_cfg = Config::Simple->new($config_file) or die "Could not read $config_file\n";
my $obis_catalog = load_catalog($catalog_file);
my $debug_enabled = ($plugin_cfg->param("VZLOGGER.VZLOGGERDEBUG") || "0") eq "1";
my $log_level = int(clean_log_level($plugin_cfg->param("VZLOGGER.LOGLEVEL"), 0));
my $log_file = $debug_enabled ? "$lbplogdir/vzlogger-native.log" : "/dev/null";

my %flat_config;
Config::Simple->import_from($config_file, \%flat_config);
my $channel_document = read_json($definitions_file);
die "Invalid channel definitions JSON: $definitions_file\n" if (-e $definitions_file && !defined($channel_document));
$channel_document ||= new_document();
$channel_document->{meters} ||= {};
my $channel_document_changed = !-e $definitions_file;

my $mqtt = read_mqtt_settings($home, $plugin_cfg);
my $base_topic = sanitize_topic($plugin_cfg->param("MAIN.MQTTTOPIC") || "smartmeter");
my $local_enabled = clean_boolean($plugin_cfg->param("VZLOGGER.LOCALENABLED"), 1);
my $local_port = clean_number($plugin_cfg->param("VZLOGGER.LOCALPORT"), 18080);
my $local_index = clean_boolean($plugin_cfg->param("VZLOGGER.LOCALINDEX"), 1);
my $local_timeout = clean_number($plugin_cfg->param("VZLOGGER.LOCALTIMEOUT"), 30);
my $local_buffer = clean_integer($plugin_cfg->param("VZLOGGER.LOCALBUFFER"), -1);
my $retry = clean_number($plugin_cfg->param("VZLOGGER.RETRY"), 30);
my $vzlogger_mode = vzlogger_enabled($plugin_cfg);

my @meters;
my %channel_mapping;
my $channel_index = 0;

foreach my $config_key (sort keys %flat_config) {
	next if ($config_key !~ /\.SERIAL\z/);

	my $section = $flat_config{$config_key};
	my $meter = $plugin_cfg->param("$section.METER") || "0";
	my $serial = $plugin_cfg->param("$section.SERIAL") || $section;
	my $mode = normalized_meter_mode($meter, $plugin_cfg->param("$section.PROTOCOL"));
	next if ($mode eq "0");

	my $meter_config;
	if ($mode eq "user") {
		my ($custom_meter, $error) = read_user_meter_json($serial);
		if ($error) {
			warn "Skipped invalid custom meter '$serial': $error\n";
			next;
		}
		my ($uuid_ok, $uuid_error) = assign_custom_channel_uuids($custom_meter, $serial, $psubfolder, $uuid_registry_dir);
		die "$uuid_error\n" if (!$uuid_ok);
		$meter_config = $custom_meter;
		enrich_user_channels($meter_config, $serial, \%channel_mapping, \$channel_index);
	} else {
		my $device = $plugin_cfg->param("$section.DEVICE") || next;
		$meter_config = standard_meter_config($section, $mode, $device, $vzlogger_mode);

		my $definitions = $channel_document->{meters}->{$serial};
		if (ref($definitions) ne "ARRAY") {
			my @available = available_channels($section);
			my @selected = config_list_values("$section.OBISCHANNELS");
			my @custom = custom_channels($section);
			my $selected_ref = defined($plugin_cfg->param("$section.OBISCHANNELS")) ? \@selected : undef;
			$definitions = initialize_channel_definitions($channel_document, $serial, $psubfolder, \@available, $selected_ref, \@custom, $obis_catalog);
			$channel_document_changed = 1;
		}
		my @channels;
		my $aggtime = clean_integer(config_scalar_value("$section.AGGTIME"), 0);
		my %identifier_counts;
		foreach my $definition (@$definitions) {
			next if (!$definition->{enabled});
			$identifier_counts{native_channel($definition, $aggtime)->{identifier}}++;
		}
		foreach my $definition (@$definitions) {
			next if (!$definition->{enabled});
			my $channel = native_channel($definition, $aggtime);
			push @channels, $channel;
			my $uuid = $definition->{uuid};
			if ($definition->{plugin_output}->{enabled}) {
				my $catalog_de = lookup_obis($obis_catalog, $channel->{identifier}, "de");
				my $catalog_en = lookup_obis($obis_catalog, $channel->{identifier}, "en");
				my $mapping_entry = {
				serial => $serial,
				name => $definition->{plugin_output}->{key},
				managed_output => JSON::PP::true,
				display_name => $definition->{display_name} || "",
				catalog_name_de => $catalog_de->{known} ? ($catalog_de->{short} || "") : "",
				catalog_name_en => $catalog_en->{known} ? ($catalog_en->{short} || "") : "",
				unit => $catalog_de->{unit} || $catalog_en->{unit} || "",
				category => $catalog_de->{category} || $catalog_en->{category} || "unknown",
				display_factor => live_display_factor($channel->{identifier}),
				identifier => $channel->{identifier},
				identifier_ambiguous => $identifier_counts{$channel->{identifier}} > 1 ? JSON::PP::true : JSON::PP::false,
				channel => "chn$channel_index",
				channel_index => $channel_index,
			};
				$channel_mapping{$uuid} = $mapping_entry;
			}
			$channel_index++;
		}
		$meter_config->{channels} = \@channels;
	}
	push @meters, $meter_config;
}

sub live_display_factor
{
	my ($identifier) = @_;
	# vzLogger exposes SML electricity counters in Wh; the catalog and plugin cache use kWh.
	return 0.001 if (defined($identifier) && $identifier =~ /\A1-0:(?:1|2)\.8\.\d+(?:\*\d+)?\z/);
	return 1;
}

my @definition_errors = validate_document($channel_document);
die "Invalid vzLogger channel definitions:\n - " . join("\n - ", @definition_errors) . "\n" if (@definition_errors);

my $mqtt_config = {
	enabled => clean_boolean($plugin_cfg->param("VZLOGGER.MQTTENABLED"), 1) ? JSON::PP::true : JSON::PP::false,
	host => $mqtt->{host},
	port => $mqtt->{port},
	keepalive => clean_number($plugin_cfg->param("VZLOGGER.MQTTKEEPALIVE"), 30),
	topic => "$base_topic/vzlogger",
	retain => clean_boolean($plugin_cfg->param("VZLOGGER.MQTTRETAIN"), 1) ? JSON::PP::true : JSON::PP::false,
	rawAndAgg => clean_boolean($plugin_cfg->param("VZLOGGER.MQTTRAWANDAGG"), 0) ? JSON::PP::true : JSON::PP::false,
	qos => clean_qos($plugin_cfg->param("VZLOGGER.MQTTQOS"), 0),
	timestamp => clean_boolean($plugin_cfg->param("VZLOGGER.MQTTTIMESTAMP"), 1) ? JSON::PP::true : JSON::PP::false,
};
my %optional_mqtt_values = (
	id => clean_text($plugin_cfg->param("VZLOGGER.MQTTID"), ""),
	user => $mqtt->{user},
	pass => $mqtt->{pass},
	cafile => $mqtt->{cafile},
	capath => $mqtt->{capath},
	certfile => $mqtt->{certfile},
	keyfile => $mqtt->{keyfile},
	keypass => $mqtt->{keypass},
);
foreach my $key (keys %optional_mqtt_values) {
	my $value = $optional_mqtt_values{$key};
	$mqtt_config->{$key} = $value if (defined($value) && $value ne "");
}

my $config = {
	retry => $retry,
	verbosity => $debug_enabled ? $log_level : 0,
	log => $log_file,
	local => {
		enabled => $local_enabled ? JSON::PP::true : JSON::PP::false,
		port => $local_port,
		index => $local_index ? JSON::PP::true : JSON::PP::false,
		timeout => $local_timeout,
		buffer => $local_buffer,
	},
	mqtt => $mqtt_config,
	meters => \@meters,
};

write_ordered_vzlogger_json($target_file, $config);
write_json($mapping_file, \%channel_mapping);
write_json_atomic($definitions_file, $channel_document) if ($channel_document_changed && !($ENV{SMARTMETER_VALIDATION_DRAFT} || ""));

if (($ENV{SMARTMETER_VALIDATION_DRAFT} || "") eq "1") {
	print "Generated temporary vzLogger configuration with " . scalar(@meters) . " configured meter(s). No saved configuration files were changed.\n";
} else {
	print "Generated $target_file with " . scalar(@meters) . " configured meter(s).\n";
}
exit 0;

sub write_json
{
	my ($file, $data) = @_;
	my ($dir) = $file =~ m{\A(.*)/[^/]+\z};
	make_path($dir) if ($dir && !-d $dir);

	open(my $fh, ">", $file) or die "Could not write $file: $!\n";
	print $fh JSON::PP->new->utf8->pretty->canonical->encode($data);
	close($fh);
}

sub standard_meter_config
{
	my ($section, $protocol, $device, $service_enabled) = @_;
	my $meter_enabled = clean_boolean(config_scalar_value("$section.ENABLED"), 1);
	my $allowskip = clean_boolean(config_scalar_value("$section.ALLOWSKIP"), 1);
	my $meter = {
		enabled => ($service_enabled && $meter_enabled) ? JSON::PP::true : JSON::PP::false,
		allowskip => $allowskip ? JSON::PP::true : JSON::PP::false,
		protocol => $protocol,
		device => $device,
	};
	set_optional_integer($meter, "aggtime", config_scalar_value("$section.AGGTIME"), 1);
	set_optional_boolean($meter, "aggfixedinterval", config_scalar_value("$section.AGGFIXEDINTERVAL"))
		if (exists($meter->{aggtime}) && $meter->{aggtime} > 0);

	if ($protocol eq "sml") {
		set_optional_integer($meter, "interval", config_scalar_value("$section.INTERVAL"), 1);
		set_optional_text($meter, "pullseq", config_scalar_value("$section.PULLSEQ"));
		set_optional_integer($meter, "baudrate", config_scalar_value("$section.BAUDRATE"), 0) if (config_scalar_value("$section.BAUDRATESET") eq "1");
		set_optional_enum($meter, "parity", configured_parity_optional($section), qr/\A(?:8n1|7e1|7o1|7n1)\z/i) if (config_scalar_value("$section.PARITYSET") eq "1");
		set_optional_boolean($meter, "use_local_time", config_scalar_value("$section.USELOCALTIME"));
	} elsif ($protocol eq "d0") {
		set_optional_integer($meter, "interval", config_scalar_value("$section.INTERVAL"), 1);
		set_optional_text($meter, "dump_file", config_scalar_value("$section.DUMPFILE"));
		set_optional_text($meter, "pullseq", config_scalar_value("$section.PULLSEQ"));
		set_optional_text($meter, "ackseq", config_scalar_value("$section.ACKSEQ"));
		set_optional_integer($meter, "baudrate", config_scalar_value("$section.BAUDRATE"), 0);
		set_optional_integer($meter, "baudrate_read", config_scalar_value("$section.BAUDRATEREAD"), 0);
		set_optional_enum($meter, "parity", configured_parity_optional($section), qr/\A(?:8n1|7e1|7o1|7n1)\z/i);
		set_optional_enum($meter, "wait_sync", config_scalar_value("$section.WAITSYNC"), qr/\A(?:off|end)\z/);
		set_optional_integer($meter, "read_timeout", first_config_value($section, "READTIMEOUT", "TIMEOUT"), 0);
		set_optional_integer($meter, "baudrate_change_delay", config_scalar_value("$section.BAUDRATECHANGEDELAY"), 0);
	} elsif ($protocol eq "oms") {
		set_optional_integer($meter, "baudrate", config_scalar_value("$section.BAUDRATE"), 0);
		set_optional_enum($meter, "key", config_scalar_value("$section.OMSKEY"), qr/\A[A-Fa-f0-9]{32}\z/);
		set_optional_boolean($meter, "mbus_debug", config_scalar_value("$section.MBUSDEBUG"));
		set_optional_boolean($meter, "use_local_time", config_scalar_value("$section.USELOCALTIME"));
	}
	return $meter;
}

sub config_scalar_value
{
	return SmartMeterVZLoggerMeterInput::config_scalar($plugin_cfg, $_[0]);
}

sub user_meter_file
{
	my ($serial) = @_;
	return "$plugin_config_dir/vzlogger_meter_" . safe_filename($serial) . ".jsonc";
}

sub read_user_meter_json
{
	my ($serial) = @_;
	my $file = user_meter_file($serial);
	return (undef, "JSONC source file does not exist") if (!-e $file);
	return (undef, "JSONC source exceeds 64 KiB") if (-s $file > 65536);
	open(my $fh, "<", $file) or return (undef, "Could not read JSONC source: $!");
	local $/;
	my $source = <$fh>;
	close($fh);
	my $result = parse_meter_jsonc($source);
	return (undef, meter_jsonc_error_text($result)) if (!$result->{valid});
	return ($result->{meter}, "");
}

sub enrich_user_channels
{
	my ($meter, $serial, $mapping, $index_ref) = @_;
	return if (!exists($meter->{channels}));
	my $meter_channel_index = 0;
	foreach my $channel (@{$meter->{channels}}) {
		my $identifier = defined($channel->{identifier}) && !ref($channel->{identifier}) ? "$channel->{identifier}" : "";
		my $index = ${$index_ref};
		die "Custom channel $meter_channel_index for reader $serial has no assigned UUID.\n"
			if (!defined($channel->{uuid}) || ref($channel->{uuid}) || $channel->{uuid} eq "");
		$channel->{api} = "null" if (!exists($channel->{api}));
		my $uuid = defined($channel->{uuid}) && !ref($channel->{uuid}) ? "$channel->{uuid}" : "";
		if ($uuid ne "") {
			my $catalog_de = lookup_obis($obis_catalog, $identifier, "de");
			my $catalog_en = lookup_obis($obis_catalog, $identifier, "en");
			$mapping->{$uuid} = {
				serial => $serial,
				name => user_channel_name($channel, $identifier, $meter_channel_index),
				catalog_name_de => $catalog_de->{known} ? ($catalog_de->{short} || "") : "",
				catalog_name_en => $catalog_en->{known} ? ($catalog_en->{short} || "") : "",
				unit => $catalog_de->{unit} || $catalog_en->{unit} || "",
				category => $catalog_de->{category} || $catalog_en->{category} || "unknown",
				display_factor => live_display_factor($identifier),
				identifier => $identifier,
				channel => "chn$index",
				channel_index => $index,
			};
		}
		${$index_ref}++;
		$meter_channel_index++;
	}
}

sub user_channel_name
{
	my ($channel, $identifier, $index) = @_;
	return "$channel->{name}" if (defined($channel->{name}) && !ref($channel->{name}) && $channel->{name} ne "");
	return obis_cache_name($identifier) if (normalize_obis_identifier($identifier));
	return "Channel_$index" if (!defined($identifier) || $identifier eq "");
	my $name = $identifier;
	$name =~ s/[^A-Za-z0-9]+/_/g;
	$name =~ s/^_+|_+$//g;
	return $name || "Channel_$index";
}

sub first_config_value
{
	my ($section, @keys) = @_;
	return SmartMeterVZLoggerMeterInput::first_config_value($plugin_cfg, $section, @keys);
}

sub configured_parity_optional
{
	my ($section) = @_;
	my $mode = config_scalar_value("$section.PARITYMODE");
	return lc($mode) if (defined($mode) && $mode =~ /\A(?:8n1|7e1|7o1|7n1)\z/i);
	return "";
}

sub default_channels
{
	return SmartMeterVZLoggerDiscovery::default_obis_channels();
}

sub write_ordered_vzlogger_json
{
	my ($file, $data) = @_;
	my ($dir) = $file =~ m{\A(.*)/[^/]+\z};
	make_path($dir) if ($dir && !-d $dir);

	open(my $fh, ">", $file) or die "Could not write $file: $!\n";
	print $fh encode_ordered_json($data, "root", 0), "\n";
	close($fh);
}

sub encode_ordered_json
{
	my ($value, $context, $level) = @_;
	my $ref = ref($value);

	if ($ref eq "HASH") {
		my @keys = ordered_keys($context, $value);
		return "{}" if (!@keys);

		my @lines;
		foreach my $key (@keys) {
			my $key_json = JSON::PP->new->utf8->allow_nonref->encode($key);
			my $child_context = child_context($context, $key);
			push @lines, ("  " x ($level + 1)) . $key_json . ": " .
				encode_ordered_json($value->{$key}, $child_context, $level + 1);
		}
		return "{\n" . join(",\n", @lines) . "\n" . ("  " x $level) . "}";
	}

	if ($ref eq "ARRAY") {
		return "[]" if (!@{$value});
		my $item_context = $context eq "meters" ? "meter" :
			$context eq "channels" ? "channel" : "default";
		my @items = map {
			("  " x ($level + 1)) . encode_ordered_json($_, $item_context, $level + 1)
		} @{$value};
		return "[\n" . join(",\n", @items) . "\n" . ("  " x $level) . "]";
	}

	return JSON::PP->new->utf8->allow_nonref->encode($value);
}

sub ordered_keys
{
	my ($context, $data) = @_;
	my %orders = (
		root => [qw(retry verbosity log local mqtt meters)],
		local => [qw(enabled port index timeout buffer)],
		mqtt => [qw(enabled host port keepalive topic id user pass retain rawAndAgg qos timestamp cafile capath certfile keyfile keypass)],
		meter => [qw(enabled allowskip aggtime aggfixedinterval protocol device interval host dump_file pullseq ackseq baudrate baudrate_read parity wait_sync read_timeout baudrate_change_delay key mbus_debug use_local_time channels)],
		channel => [qw(api uuid identifier)],
	);
	my @preferred = @{$orders{$context} || []};
	my %seen;
	my @keys = grep { exists($data->{$_}) && !$seen{$_}++ } @preferred;
	push @keys, grep { !$seen{$_}++ } sort keys %{$data};
	return @keys;
}

sub child_context
{
	my ($context, $key) = @_;
	return "local" if ($context eq "root" && $key eq "local");
	return "mqtt" if ($context eq "root" && $key eq "mqtt");
	return "meters" if ($context eq "root" && $key eq "meters");
	return "channels" if ($context eq "meter" && $key eq "channels");
	return "default";
}

sub clean_integer
{
	my ($value, $default) = @_;
	return int($value) if (defined($value) && $value =~ /\A-?\d+\z/);
	return $default;
}

sub clean_boolean
{
	my ($value, $default) = @_;
	return int($value) if (defined($value) && $value =~ /\A[01]\z/);
	return $default;
}

sub clean_text
{
	my ($value, $default) = @_;
	return $default if (!defined($value) || $value eq "");
	$value =~ s/[\r\n]//g;
	return $value;
}

sub clean_log_level
{
	my ($value, $default) = @_;
	return $value if (defined($value) && $value =~ /\A(?:0|1|3|5|10|15)\z/);
	return $default;
}

sub available_channels
{
	my ($section) = @_;
	my $serial = $plugin_cfg->param("$section.SERIAL") || $section;
	my @channels = read_obis_discovery_cache($serial);
	return sort_obis_channels(@channels) if (obis_discovery_cache_exists($serial));

	my %seen;
	foreach my $identifier (config_list_values("$section.OBISCHANNELS")) {
		$identifier = normalize_obis_identifier($identifier);
		next if (!$identifier || $seen{$identifier});
		push @channels, {
			identifier => $identifier,
			name => obis_cache_name($identifier),
		};
		$seen{$identifier} = 1;
	}

	return sort_obis_channels(@channels);
}

sub config_list_values
{
	return SmartMeterVZLoggerMeterInput::config_list($plugin_cfg, $_[0]);
}

sub custom_channels
{
	my ($section) = @_;
	my $value = $plugin_cfg->param("$section.OBISCUSTOM") || "";
	my @channels;
	foreach my $line (split(/\\n|\r?\n|,|;/, $value)) {
		my $identifier = normalize_obis_identifier($line);
		push @channels, $identifier if ($identifier);
	}
	return sort_obis_channels(@channels);
}

sub normalize_obis_identifier
{
	return SmartMeterVZLoggerDiscovery::normalize_obis_identifier($_[0]);
}

sub obis_cache_name
{
	return SmartMeterVZLoggerDiscovery::obis_cache_name($_[0]);
}

sub read_obis_discovery_cache
{
	return SmartMeterVZLoggerDiscovery::read_discovery_cache($plugin_config_dir, $_[0]);
}

sub obis_discovery_cache_file
{
	return SmartMeterVZLoggerDiscovery::discovery_cache_file($plugin_config_dir, $_[0]);
}

sub obis_discovery_cache_exists
{
	return SmartMeterVZLoggerDiscovery::discovery_cache_exists($plugin_config_dir, $_[0]);
}

sub sort_obis_channels
{
	return SmartMeterVZLoggerDiscovery::sort_obis_channels(@_);
}
