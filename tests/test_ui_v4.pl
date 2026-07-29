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
	webfrontend/htmlauth/smartmeter-vzlogger.css
	webfrontend/htmlauth/smartmeter-vzlogger.js
	webfrontend/htmlauth/smartmeter-settings.js
	webfrontend/htmlauth/smartmeter-settings.css
	webfrontend/htmlauth/vzlogger_live.cgi
	webfrontend/htmlauth/vzlogger_live.js
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
like($sources{'webfrontend/htmlauth/index.cgi'}, qr/my \$asset_version = "\$version-\$asset_mtime"/, "settings assets combine the plugin version with their newest modification time");
like($sources{'webfrontend/htmlauth/vzlogger_live.cgi'}, qr/pluginversion\(\) \. "-\$asset_mtime"/, "live assets combine the plugin version with their newest modification time");

my $vzlogger = $sources{'templates/settings.html'} . $sources{'webfrontend/htmlauth/smartmeter-settings.js'};
like($vzlogger, qr/<details\b[^>]*\blb-collapsible\b/, "vzLogger uses native details collapsibles");
like($vzlogger, qr/<details\b(?=[^>]*\bid="recovery_settings_panel")(?=[^>]*\blb-collapsible\b)(?=[^>]*\bopen\b)[^>]*>/, "recovery settings use an initially open persistent native collapsible");
like($vzlogger, qr/<dialog\b(?=[^>]*\bid="ir_scan_overlay")(?=[^>]*\baction-overlay-standard\b)[^>]*>/, "I/R scan uses the single standard-width native action dialog");
like($vzlogger, qr/<dialog\b(?=[^>]*\bid="obis_search_overlay")(?=[^>]*\baction-overlay-standard\b)[^>]*>/, "OBIS discovery uses the single standard-width native action dialog");
like($vzlogger, qr/<dialog\b(?=[^>]*\bid="service_action_overlay")(?=[^>]*\baction-overlay-standard\b)[^>]*>/, "service actions use the single standard-width native action dialog");
like($vzlogger, qr/<dialog\b(?=[^>]*\bid="configuration_action_overlay")(?=[^>]*\baction-overlay-wide\b)[^>]*>/, "configuration actions use the single wide native action dialog");
like($vzlogger, qr/id="obis_search_spinner".*?getElementById\("obis_search_spinner"\)/s, "OBIS discovery updates its own spinner explicitly");
unlike($vzlogger, qr/querySelector\("\.obis-search-spinner"\)/, "OBIS discovery does not modify another action dialog's spinner");
like($vzlogger, qr/<dialog\b[^>]*\blb-modal\b/, "vzLogger uses native dialog modals");
like($vzlogger, qr/\bshowModal\s*\(/, "vzLogger opens native dialogs");
like($vzlogger, qr/class="ch-api lb-select"/, "dynamic channel API selects use V4 classes directly");
like($vzlogger, qr/class="ch-obis lb-input"/, "dynamic channel inputs use V4 classes directly");
like($vzlogger, qr/channel_labels\.display.*?config-key-spacer.*?class="ch-display lb-input"/, "display name reserves the desktop configuration-key row before its input");
like($vzlogger, qr/\bpi-trash\b/, "dynamic destructive actions use PrimeIcons");
for my $key (qw(CHANNEL_SOURCE CHANNEL_API_TARGET CHANNEL_API_NONE CHANNEL_BRIDGE_OUTPUT CHANNEL_STATE_ENABLED CHANNEL_STATE_DISABLED)) {
	like($vzlogger, qr/\bVZLOGGER\.\Q$key\E\b/, "channel summary references $key");
}
like($vzlogger, qr/<option value="null">'\+html_text\(channel_labels\.apiNoneOption\)\+'<\/option>/, "null API option uses its explanatory label without changing the submitted value");

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

my $styles = $sources{'webfrontend/htmlauth/smartmeter-v4.css'} . $sources{'webfrontend/htmlauth/smartmeter-vzlogger.css'} . $sources{'webfrontend/htmlauth/smartmeter-settings.css'};
like($styles, qr/\.recovery-loxone-fields\s*\{[^}]*grid-template-columns/s, "Loxone copy-and-paste fields use a responsive grid");
like($styles, qr/recovery-settings-panel \.service-controls > \.lb-btn\s*\{[^}]*width:\s*100%[^}]*white-space:\s*normal/s, "recovery actions fit and wrap in compact mobile controls");
like($styles, qr/implementation-tabs \.lb-btn-active/, "active implementation tab has an explicit V4 state");
like($styles, qr/implementation-tabs\s*\{[^}]*border:\s*0\s*!important/s, "implementation tab group has no redundant outer border");
like($styles, qr/implementation-tabs \.lb-btn\s*\{[^}]*margin:\s*0\s*!important/s, "implementation tabs do not retain framework margins that clip the last border");
like($styles, qr/implementation-tabs \.lb-btn\s*\{[^}]*border:\s*1px\s+solid/s, "each implementation tab retains its complete individual border");
like($styles, qr/input:checked \+ \.lb-toggle-slider::before/, "toggle knob has an explicit checked position");
like($styles, qr/details\.lb-collapsible\[open\] > summary/, "open collapsible headers have a distinct state");
unlike($vzlogger . $shared, qr/\blb-btn-danger\b/, "removal actions use a restrained secondary style");
like($styles, qr/input\.obis-number-spinner\s*\{[^}]*height:\s*40px/s, "storage input uses the standard action height");
like($styles, qr/obis-storage-clear\.lb-btn\s*\{[^}]*height:\s*40px/s, "storage clear button matches the input height");
like($sources{'webfrontend/htmlauth/smartmeter-vzlogger.js'}, qr/PREFIX\s*=\s*"smartmeter-vzlogger"/, "channel collapsible state uses a dedicated local storage namespace");
like($vzlogger, qr/channel_details_storage_key\(serial,\s*uuid\)/, "channel collapsible state is keyed by meter and channel UUID");
like($vzlogger, qr/container\.addEventListener\('toggle'.*?persist_channel_details/s, "channel collapsible changes are persisted through delegated toggle events");
like($vzlogger, qr/data-lazy="1"/, "channel detail controls use a lazy-rendering placeholder");
like($vzlogger, qr/delete grid\.dataset\.lazy/, "rendered channel details clear their lazy placeholder state");
like($vzlogger, qr/if\(open\) render_channel_details/, "only restored open channel details render immediately");
like($vzlogger, qr/initializeDeferredPanel/, "closed meter panels defer their initialization");
my ($aggtime_input) = $vzlogger =~ /([^\r\n]*id="<TMPL_VAR NAME=SERIAL>_aggtime"[^\r\n]*)/;
like($aggtime_input || "", qr/update_meter_enabled/, "aggtime updates channel availability immediately");
unlike($aggtime_input || "", qr/render_channel_editor/, "aggtime input does not rebuild every channel card");
like($vzlogger, qr/id="<TMPL_VAR NAME=SERIAL>_aggfixedinterval"/, "fixed aggregation interval control is rendered for standard meters");
like($vzlogger, qr/set_control_disabled\(\$\("#" \+ serial \+ "_aggfixedinterval"\).*?_aggtime/s, "fixed aggregation interval follows active aggtime immediately");
like($vzlogger, qr/class="config-key"><code>meters\[\]\.aggfixedinterval<\/code>/, "native vzLogger fields expose their generated configuration path");
unlike($vzlogger, qr/CONFIG_FIELD_PLUGIN|kein Feld in vzlogger\.conf|not a field in vzlogger\.conf/, "plugin-only settings do not show a redundant configuration marker");
like($styles, qr/\.config-key\s*\{[^}]*overflow-wrap:\s*anywhere/s, "configuration paths wrap safely on narrow screens");
like($styles, qr/\.config-key-spacer\s*\{[^}]*visibility:\s*hidden/s, "display name spacer matches the hidden desktop configuration-key row");
like($styles, qr/\@media\(max-width:800px\).*?\.config-key-spacer\s*\{[^}]*display:\s*none/s, "display name spacer is removed from the single-column mobile layout");
like($vzlogger, qr/<td colspan="4">\s*<div class="recovery-endpoints-title">.*?<div class="recovery-endpoints">/s, "Loxone copy-and-paste blocks receive the full desktop table width");

my $live = $sources{'webfrontend/htmlauth/vzlogger_live.js'};
like($live, qr/function ingest\(data\).*?return changed;/s, "live ingestion reports whether history changed");
like($live, qr/diagnosticHtml\(i18n\.noChannels, i18n\.noChannelsHint\)/, "empty live responses show channel-specific troubleshooting guidance");
like($live, qr/error\.message === i18n\.dataFailed \? i18n\.dataFailedHint/, "live-data failures show service and HTTP troubleshooting guidance");
like($live, qr/firstRender \|\| metadataChanged \|\| responseChanged \|\| historyChanged.*?renderTable\(data\); updateChart\(\);/s, "live rendering is gated by first render or changed data");
like($live, qr/visibilitychange.*?renderTable\(currentData\); if \(historyInitialized\) updateChart\(\);/s, "returning to the live page forces a current render after safe history initialization");
like($live, qr/backgroundColor:\s*colorWithAlpha\(style\.color,\s*0\.04\).*?fill:\s*Live\.isPower\(meta\)\s*\?\s*\{\s*target:\s*"origin"\s*\}\s*:\s*false/s, "live power curves use a subtle fill toward zero only");
like($live, qr/pointRadius:\s*0,\s*pointHoverRadius:\s*4,\s*pointHitRadius:\s*8/, "live hover reveals the measurement point without permanent markers");
unlike($live, qr/function focusDataset\(|onHover:\s*\([^)]*\)\s*=>\s*focusDataset|onClick:\s*\([^)]*legendItem[^)]*\)\s*=>\s*focusDataset/, "live hover and legend clicks do not restyle or reorder datasets");
like($live, qr/visibility\.set\(dataset\.uuid,\s*chart\.isDatasetVisible\(index\)\).*?chart\.data\.datasets\s*=\s*datasets;.*?chart\.setDatasetVisibility\(index,\s*visibility\.get\(dataset\.uuid\)\)/s, "live updates preserve legend visibility by channel UUID");
like($live, qr/const historyInitialization = initializeHistoryStorage\(\);.*?await requestLiveData\(false\);.*?renderTable\(initial\.data\).*?await historyInitialization;/s, "the first live table renders while persistent chart history loads");
like($live, qr/requestIdleCallback\(compactNext,\s*\{\s*timeout:\s*1000\s*\}\)/, "browser history compaction is spread across idle callbacks");
unlike($live, qr/\.filter\(point => point\.value >= 0\)\.sort|\.filter\(point => point\.value < 0\)\.sort/, "live summary peaks do not sort complete histories");
like($live, qr/function schedule\(immediate\).*?!historyInitialized/s, "polling cannot race browser-history initialization");
like($live, qr/POLL_INTERVAL_VALUES\s*=\s*\[2000,\s*10000,\s*30000,\s*60000,\s*120000,\s*300000\]/, "live polling exposes the supported browser-local intervals");
like($vzlogger, qr/\.\/obis_status\.cgi/, "OBIS discovery polls the lightweight authenticated endpoint");
like($vzlogger, qr/setTimeout\(sync_channel_definitions,\s*200\)/, "channel JSON serialization is debounced");
like($vzlogger, qr/new FormData\(form\)/, "configuration actions retain form-based AJAX submission");

my $help = read_file("webfrontend/htmlauth/help.cgi");
like($help, qr/LoxBerry::Web::lbheader\s*\([^;]*["']nojqm["']/s, "local help uses the V4 header without jQuery Mobile");
like($help, qr/templates?\/plugins|lbptemplatedir/, "local help uses the installed plugin template");
my $help_template = read_file("templates/multi/help.html");
like($help_template, qr/\bHELP\.IMPLEMENTATIONS_TITLE\b/, "local help is language-resource driven");
like($help_template, qr/MANUAL_URL/, "local help receives a version-bound manual URL");
unlike($help_template, qr/(?:tree|blob)\/master\/docs/, "local help does not hard-code development documentation");
like($help, qr/Smartmeter-V\$version.*User-Guide\.\$language\.md/s, "local help builds a language-specific release-tag URL");

my $legacy_settings = read_file("templates/multi/main.html");
like($legacy_settings, qr/name="udpport".*?data-validation-allowing="range\[1;65535\]"/s, "Legacy UDP accepts the complete port range");
like($vzlogger, qr/name="vzlogger_localport".*?data-validation-allowing="range\[1;65535\]"/s, "local vzLogger HTTP accepts the complete port range");
like($vzlogger, qr/name="udpport".*?data-validation-allowing="range\[1;65535\]"/s, "bridge UDP accepts the complete port range");
unlike($legacy_settings . $vzlogger, qr/data-validation-allowing="range\[1;(?:65000|65534)\]"/, "port controls have no outdated upper browser limit");
like($vzlogger, qr/id="vzlogger_mqttqos".*?<option value="0">0<\/option><option value="1">1<\/option>/s, "standard MQTT QoS offers only 0 and 1");
unlike($vzlogger, qr/id="vzlogger_mqttqos"(?:(?!<\/select>).)*<option value="2">/s, "standard MQTT QoS does not offer 2");

done_testing();
