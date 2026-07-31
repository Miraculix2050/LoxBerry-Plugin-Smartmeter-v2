package SmartMeterVZLoggerStatus;

use strict;
use warnings;
use Exporter qw(import);
use JSON::PP ();
use SmartMeterVZLoggerExpert qw(read_text validate_expert_text expert_configs_equal);

our @EXPORT_OK = qw(
	read_service_runtime generated_config_status expert_status
	service_status_class service_status_data build_service_snapshot encode_service_snapshot
);

sub encode_service_snapshot
{
	my ($snapshot) = @_;
	die "service snapshot must be a JSON object" if (ref($snapshot) ne "HASH");
	return JSON::PP->new->utf8->canonical->encode($snapshot);
}

sub read_service_runtime
{
	my (@services) = @_;
	my %runtime = map { $_ => { state => "unknown", pid => "" } } @services;
	if (open(my $fh, "-|", "systemctl", "show", "--property=Id", "--property=ActiveState", "--property=MainPID", "--no-pager", @services)) {
		my %properties;
		my $apply = sub {
			(my $service = $properties{Id} || "") =~ s/\.service\z//;
			return if (!$service || !$runtime{$service});
			$runtime{$service}->{state} = $properties{ActiveState} if (($properties{ActiveState} || "") ne "");
			$runtime{$service}->{pid} = $properties{MainPID}
				if (($properties{MainPID} || "") ne "" && $properties{MainPID} ne "0");
		};
		while (my $line = <$fh>) {
			chomp($line);
			if ($line eq "") {
				$apply->();
				%properties = ();
				next;
			}
			my ($name, $value) = split(/=/, $line, 2);
			$properties{$name} = $value if (defined($value));
		}
		$apply->() if (%properties);
		close($fh);
	}
	return \%runtime;
}

sub _read_json_file
{
	my ($file) = @_;
	return undef if (!open(my $fh, "<", $file));
	local $/;
	my $decoded = eval { JSON::PP->new->utf8->decode(<$fh> || "") };
	close($fh);
	return $@ ? undef : $decoded;
}

sub generated_config_status
{
	my (%options) = @_;
	my $config_dir = $options{config_dir} || die "config_dir is required";
	my $bin_dir = $options{bin_dir} || die "bin_dir is required";
	my $file = "$config_dir/vzlogger.conf";
	my $config = _read_json_file($file);
	my $status = { present => -e $file ? 1 : 0, valid => 0, mqtt_enabled => 0, mqtt_timestamp => 0 };
	return $status if (ref($config) ne "HASH");
	$status->{mqtt_enabled} = ref($config->{mqtt}) eq "HASH" && $config->{mqtt}->{enabled} ? 1 : 0;
	$status->{mqtt_timestamp} = ref($config->{mqtt}) eq "HASH" && $config->{mqtt}->{timestamp} ? 1 : 0;
	return $status if (ref($config->{meters}) ne "ARRAY" || !@{$config->{meters}});
	return $status if (!$options{expert_mode} && !-e "$config_dir/vzlogger_channels.json");
	if ($options{assume_valid}) {
		$status->{valid} = 1;
		return $status;
	}
	my $validator = "$bin_dir/vzlogger_validate.pl";
	return $status if (!-e $validator);
	my $validator_runner = $options{validator_runner} || sub {
		my ($program) = @_;
		return 0 if (!open(my $fh, "-|", $^X, $program));
		1 while (<$fh>);
		close($fh);
		return (($? >> 8) == 0) ? 1 : 0;
	};
	$status->{valid} = $validator_runner->($validator) ? 1 : 0;
	return $status;
}

sub expert_status
{
	my (%options) = @_;
	my $config_dir = $options{config_dir} || die "config_dir is required";
	my $file = "$config_dir/vzlogger_expert.conf";
	return { present => 0, valid => 0, message => "" } if (!-e $file);
	my $result = validate_expert_text(read_text($file));
	return {
		present => 1,
		valid => $result->{valid} ? 1 : 0,
		message => join("\n", @{$result->{errors} || []}, @{$result->{warnings} || []}),
	};
}

sub service_status_class
{
	my ($state, $expected) = @_;
	return $state eq "active" ? "service-status-ok" : "service-status-error" if ($expected);
	return "service-status-idle" if ($state eq "inactive");
	return "service-status-warning" if ($state eq "active" || $state eq "activating");
	return "service-status-error";
}

sub service_status_data
{
	my (%options) = @_;
	my $runtime = $options{runtime} || { state => "unknown", pid => "" };
	my $state = $runtime->{state} || "unknown";
	my $running = $state eq "active";
	return {
		state => $state,
		pid => $runtime->{pid} || "",
		installed => $options{installed} ? JSON::PP::true : JSON::PP::false,
		running => $running ? JSON::PP::true : JSON::PP::false,
		status_class => service_status_class($state, $options{expected}),
		can_stop => $running ? JSON::PP::true : JSON::PP::false,
	};
}

sub build_service_snapshot
{
	my (%options) = @_;
	my $settings = $options{settings} || {};
	my $runtime = $options{runtime} || {};
	my $installed = $options{installed} || {};
	my $vzlogger_expected = $settings->{vzlogger_enabled} ? 1 : 0;
	my $mqtt_enabled = $settings->{mqtt_enabled} ? 1 : 0;
	my $bridge_enabled = $settings->{bridge_enabled} ? 1 : 0;
	my $bridge_expected = $vzlogger_expected && $mqtt_enabled && $bridge_enabled;
	my $response = {
		ok => JSON::PP::true,
		services => {
			vzlogger => service_status_data(
				runtime => $runtime->{vzlogger}, installed => $installed->{vzlogger}, expected => $vzlogger_expected),
			bridge => service_status_data(
				runtime => $runtime->{"smartmeter-v2-vzlogger-bridge"},
				installed => $installed->{"smartmeter-v2-vzlogger-bridge"}, expected => $bridge_expected),
		},
	};
	return $response if (!$options{details});

	my $config = $options{config_status} || generated_config_status(
		config_dir => $options{config_dir}, bin_dir => $options{bin_dir}, expert_mode => $settings->{expert_mode});
	my $expert = $options{expert_status} || expert_status(config_dir => $options{config_dir});
	my $expert_applied = exists($options{expert_applied}) ? $options{expert_applied}
		: expert_configs_equal("$options{config_dir}/vzlogger_expert.conf", "$options{config_dir}/vzlogger.conf");
	my $vzlogger_startable = $config->{valid} ? 1 : 0;
	$vzlogger_startable = 0 if ($settings->{expert_mode} && (!$expert->{valid} || !$expert_applied));
	my $bridge_startable = $vzlogger_startable && $mqtt_enabled && $config->{mqtt_enabled};

	$response->{applied} = {
		vzlogger_enabled => $vzlogger_expected ? JSON::PP::true : JSON::PP::false,
		mqtt_enabled => $mqtt_enabled ? JSON::PP::true : JSON::PP::false,
		bridge_enabled => $bridge_enabled ? JSON::PP::true : JSON::PP::false,
	};
	$response->{config} = {
		present => $config->{present} ? JSON::PP::true : JSON::PP::false,
		valid => $config->{valid} ? JSON::PP::true : JSON::PP::false,
		mqtt_enabled => $config->{mqtt_enabled} ? JSON::PP::true : JSON::PP::false,
		mqtt_timestamp => $config->{mqtt_timestamp} ? JSON::PP::true : JSON::PP::false,
		expert_mode => $settings->{expert_mode} ? JSON::PP::true : JSON::PP::false,
		expert_present => $expert->{present} ? JSON::PP::true : JSON::PP::false,
		expert_valid => $expert->{valid} ? JSON::PP::true : JSON::PP::false,
		expert_message => $expert->{message} || "",
		expert_applied => $expert_applied ? JSON::PP::true : JSON::PP::false,
	};
	for my $entry ([vzlogger => $vzlogger_startable], [bridge => $bridge_startable]) {
		my ($name, $startable) = @$entry;
		$response->{services}->{$name}->{config_valid} = $startable ? JSON::PP::true : JSON::PP::false;
		$response->{services}->{$name}->{can_start} = $startable ? JSON::PP::true : JSON::PP::false;
		$response->{services}->{$name}->{can_restart} = $startable ? JSON::PP::true : JSON::PP::false;
	}
	return $response;
}

1;
