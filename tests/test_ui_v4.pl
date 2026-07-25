#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use Test::More;

sub read_file
{
	my ($relative) = @_;
	my $path = "$FindBin::Bin/../$relative";
	open(my $fh, "<", $path) or die "Could not read $path: $!";
	local $/;
	my $text = <$fh>;
	close($fh);
	return $text;
}

my %sources = map { $_ => read_file($_) } qw(
	templates/settings.html
	templates/multi/main.html
	webfrontend/htmlauth/index.cgi
	webfrontend/htmlauth/index_legacy.cgi
	webfrontend/htmlauth/smartmeter-ui.js
	webfrontend/htmlauth/smartmeter-v4.css
);

foreach my $template (qw(templates/settings.html templates/multi/main.html)) {
	my $source = $sources{$template};
	unlike($source, qr/\bdata-(?:role|mini|inline|icon|native-menu|collapsed|ajax|theme|transition|rel)=/i, "$template contains no jQuery Mobile attributes");
	unlike($source, qr/\bui-(?:btn|select|input|flipswitch|collapsible|disabled|navbar|mini)\b/i, "$template contains no jQuery Mobile classes");
	unlike($source, qr/\.(?:flipswitch|selectmenu|collapsible|checkboxradio|enhanceWithin)\s*\(/, "$template contains no jQuery Mobile widget calls");
	like($source, qr/smartmeter-v4\.css/, "$template loads the shared V4 stylesheet");
	like($source, qr/smartmeter-ui\.js/, "$template loads the shared V4 behavior");
	like($source, qr/\blb-content\b/, "$template uses the LoxBerry content layout");
	like($source, qr/\blb-btn-group\b/, "$template uses LoxBerry button-group navigation");
	like($source, qr/\blb-toggle\b/, "$template uses native LoxBerry toggles");
}

foreach my $cgi (qw(webfrontend/htmlauth/index.cgi webfrontend/htmlauth/index_legacy.cgi)) {
	like($sources{$cgi}, qr/LoxBerry::Web::lbheader\s*\([^;]*["']nojqm["']/s, "$cgi explicitly disables jQuery Mobile");
}

my $vzlogger = $sources{'templates/settings.html'};
like($vzlogger, qr/<details\b[^>]*\blb-collapsible\b/, "vzLogger uses native details collapsibles");
like($vzlogger, qr/<dialog\b[^>]*\blb-modal\b/, "vzLogger uses native dialog modals");
like($vzlogger, qr/\bshowModal\s*\(/, "vzLogger opens native dialogs");
like($vzlogger, qr/class="ch-api lb-select"/, "dynamic channel API selects use V4 classes directly");
like($vzlogger, qr/class="ch-obis lb-input"/, "dynamic channel inputs use V4 classes directly");
like($vzlogger, qr/\bpi-trash\b/, "dynamic destructive actions use PrimeIcons");

for my $field (qw(implementation read sendudp)) {
	like($vzlogger, qr/id="${field}_value"\s+name="$field"/, "vzLogger preserves submitted $field field name");
	like($vzlogger, qr/id="$field"\s+class="smartmeter-toggle-input"/, "vzLogger preserves visible $field toggle id");
}

my $legacy = $sources{'templates/multi/main.html'};
for my $field (qw(implementation read sendudp sendmqtt sendhtml)) {
	like($legacy, qr/id="${field}_value"\s+name="$field"/, "Legacy preserves submitted $field field name");
	like($legacy, qr/id="$field"\s+class="smartmeter-toggle-input"/, "Legacy preserves visible $field toggle id");
}

my $shared = $sources{'webfrontend/htmlauth/smartmeter-ui.js'};
for my $helper (qw(smartmeterToggleValue smartmeterSetToggleValue smartmeterSyncToggle smartmeterSetToggleDisabled smartmeterSetLinkDisabled)) {
	like($shared, qr/\b\Q$helper\E\b/, "shared UI exports $helper");
}
like($shared, qr/\blb-form-label\b/, "shared UI applies LoxBerry form-label classes");
like($shared, qr/\blb-form-field\b/, "shared UI applies LoxBerry form-field classes");
like($shared, qr/\bpi-save\b/, "shared UI applies PrimeIcons to primary actions");

my $styles = $sources{'webfrontend/htmlauth/smartmeter-v4.css'};
like($styles, qr/implementation-tabs \.lb-btn-active/, "active implementation tab has an explicit V4 state");
like($styles, qr/implementation-tabs\s*\{[^}]*border:\s*0\s*!important/s, "implementation tab group has no redundant outer border");
like($styles, qr/implementation-tabs \.lb-btn\s*\{[^}]*margin:\s*0\s*!important/s, "implementation tabs do not retain framework margins that clip the last border");
like($styles, qr/implementation-tabs \.lb-btn\s*\{[^}]*border:\s*1px\s+solid/s, "each implementation tab retains its complete individual border");
like($styles, qr/input:checked \+ \.lb-toggle-slider::before/, "toggle knob has an explicit checked position");
like($styles, qr/details\.lb-collapsible\[open\] > summary/, "open collapsible headers have a distinct state");
unlike($vzlogger . $shared, qr/\blb-btn-danger\b/, "removal actions use a restrained secondary style");
like($vzlogger, qr/input\.obis-number-spinner\s*\{[^}]*height:\s*40px/s, "storage input uses the standard action height");
like($vzlogger, qr/obis-storage-clear\.lb-btn\s*\{[^}]*height:\s*40px/s, "storage clear button matches the input height");
like($vzlogger, qr/smartmeter-vzlogger-channel-details:/, "channel collapsible state uses a dedicated local storage namespace");
like($vzlogger, qr/channel_details_storage_key\(serial,\s*uuid\)/, "channel collapsible state is keyed by meter and channel UUID");
like($vzlogger, qr/channel_details\.addEventListener\(['"]toggle['"]/, "channel collapsible changes are persisted through the native toggle event");

my $help = read_file("webfrontend/htmlauth/help.cgi");
like($help, qr/LoxBerry::Web::lbheader\s*\([^;]*["']nojqm["']/s, "local help uses the V4 header without jQuery Mobile");
like($help, qr/templates?\/plugins|lbptemplatedir/, "local help uses the installed plugin template");
like(read_file("templates/multi/help.html"), qr/\bHELP\.IMPLEMENTATIONS_TITLE\b/, "local help is language-resource driven");

done_testing();
