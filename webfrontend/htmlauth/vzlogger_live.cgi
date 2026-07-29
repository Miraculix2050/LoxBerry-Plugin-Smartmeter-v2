#!/usr/bin/perl
use strict;
use warnings;
use CGI;
use Config::Simple;
use HTML::Template;
use JSON::PP;
use LoxBerry::System;
use lib $lbpbindir;
use SmartMeterVZLoggerChannels qw(load_catalog lookup_obis);
use SmartMeterVZLoggerHttp qw(fetch_local_json);

my $cgi = CGI->new;
my $mapping_file = "$lbpconfigdir/vzlogger_channels.json";
if ($cgi->param("meta")) {
	my $cfg = Config::Simple->new("$lbpconfigdir/smartmeter.cfg");
	my $catalog = load_catalog("$lbptemplatedir/obis_catalog.json");
	my $metadata_version = metadata_version($mapping_file, "$lbpconfigdir/smartmeter.cfg", "$lbptemplatedir/obis_catalog.json");
	print $cgi->header(-type => "application/json", -charset => "utf-8", -expires => "now");
	print JSON::PP->new->utf8->canonical->encode(read_channel_metadata($mapping_file, $cfg, $metadata_version, $catalog));
	exit 0;
}

my $template = HTML::Template->new(
	filename => "$lbptemplatedir/vzlogger_live.html",
	global_vars => 1,
	die_on_bad_params => 0,
);
my %L = LoxBerry::System::readlanguage($template, "language.ini");
if ($cgi->param("json")) {
	my $cfg = Config::Simple->new("$lbpconfigdir/smartmeter.cfg");
	my $port = $cfg ? ($cfg->param("VZLOGGER.LOCALPORT") || 18080) : 18080;
	my $metadata_version = metadata_version($mapping_file, "$lbpconfigdir/smartmeter.cfg", "$lbptemplatedir/obis_catalog.json");
	my $json = read_live_json($port);
	print $cgi->header(
		-type => "application/json",
		-charset => "utf-8",
		-expires => "now",
		-X_Smartmeter_Metadata_Version => $metadata_version,
	);
	print $json;
	exit 0;
}
print $cgi->header(-type => "text/html", -charset => "utf-8", -expires => "now");
print $template->output();

sub metadata_version {
	my (@files) = @_;
	return join("-", map {
		my @stat = stat($_);
		@stat ? "$stat[9]:$stat[7]" : "0:0";
	} @files);
}

sub read_channel_metadata {
	my ($file, $plugin_cfg, $version, $obis_catalog) = @_;
	my %channels;
	if (-e $file && open(my $fh, "<", $file)) {
		local $/;
		my $text = <$fh> || "";
		close($fh);
		my $mapping = eval { JSON::PP->new->utf8->decode($text) };
		if (!$@ && ref($mapping) eq "HASH") {
			foreach my $uuid (keys %$mapping) {
				my $entry = $mapping->{$uuid};
				next if (ref($entry) ne "HASH");
				my $serial = $entry->{serial} || "unknown";
				my $catalog_entry = lookup_obis($obis_catalog, $entry->{identifier} || "", "en");
				$channels{lc($uuid)} = {
					serial => $serial,
					head_name => $plugin_cfg ? ($plugin_cfg->param("$serial.NAME") || $serial) : $serial,
					name => $entry->{name} || "",
					display_name => $entry->{display_name} || "",
					catalog_name_de => $entry->{catalog_name_de} || "",
					catalog_name_en => $entry->{catalog_name_en} || "",
					unit => $entry->{unit} || "",
					category => $catalog_entry->{category} || $entry->{category} || "unknown",
					display_factor => defined($entry->{display_factor}) ? 0 + $entry->{display_factor} : 1,
					identifier => $entry->{identifier} || "",
					channel => $entry->{channel} || "",
					channel_index => defined($entry->{channel_index}) ? int($entry->{channel_index}) : 0,
				};
			}
		}
	}
	return {
		version => $version,
		channels => \%channels,
	};
}

sub read_live_json {
	my ($port) = @_;
	my ($json, $error) = fetch_local_json($port);
	return $json if (defined($json));
	my $message = $error eq "unavailable" ? $L{'VZLOGGER.LIVE_HTTP_UNAVAILABLE'} : $L{'VZLOGGER.LIVE_INVALID_RESPONSE'};
	return JSON::PP->new->encode({ error => $message });
}
