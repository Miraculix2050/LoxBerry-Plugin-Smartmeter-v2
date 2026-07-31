@{
	Version = 1

	Groups = @{
		Documentation = @("documentation-links")
		Languages = @("language-resources", "ui-v4", "documentation-links")
		Channels = @("vzlogger-channels", "channel-model", "channel-model-parity", "vzlogger-generator", "vzlogger-validator", "vzlogger-custom-channels")
		Configuration = @("vzlogger-generator", "vzlogger-validator", "vzlogger-expert", "vzlogger-config-validation", "vzlogger-inputs")
		Runtime = @("vzlogger-runtime", "vzlogger-config-validation", "vzlogger-status", "service-policy", "system-runner", "diagnostics")
		Bridge = @("vzlogger-bridge", "vzlogger-http", "loxberry-native-integration", "vzlogger-config-validation")
		Obis = @("obis-status", "discovery-job", "vzlogger-channels", "vzlogger-config-validation")
		WebSecurity = @("web-security", "recovery")
		Ui = @("ui-v4", "settings-modules", "language-resources", "web-security", "vzlogger-status", "vzlogger-config-validation")
		LiveUi = @("vzlogger-live", "ui-v4", "language-resources")
		Lifecycle = @("upgrade-2-1", "lifecycle-v4", "bridge-service-lifecycle", "recovery")
		Metadata = @("release-metadata", "validate-development-metadata", "documentation-links", "lifecycle-v4")
		DeploymentTooling = @("deploy-line-endings")
		Runner = @("test-runner")
		Vendor = @("chartjs-integrity", "vzlogger-live")
	}

	Rules = @(
		@{ Patterns = @("AGENTS.md", "README.md", "CHANGELOG.md", "docs/**"); Groups = @("Documentation"); Device = "none"; Browser = "none" }
		@{ Patterns = @("templates/lang/**"); Groups = @("Languages"); Device = "installed rendering only when needed"; Browser = "both languages at 390x844; add sizes only for wrapping risk" }
		@{ Patterns = @("templates/obis_catalog.json", "templates/meter_templates.json", "bin/SmartMeterVZLoggerChannel*.pm", "bin/SmartMeterVZLoggerCustomChannels.pm"); Groups = @("Channels"); Device = "none unless LoxBerry wiring changed"; Browser = "none unless rendered channel behavior changed" }
		@{ Patterns = @("bin/SmartMeterVZLoggerConfig.pm", "bin/vzlogger_config.pl", "bin/vzlogger_validate.pl", "bin/SmartMeterVZLoggerExpert.pm"); Groups = @("Configuration"); Device = "targeted Save/Apply only for installed integration changes"; Browser = "changed workflow at Chrome primary sizes when UI behavior changed" }
		@{ Patterns = @("bin/SmartMeterVZLoggerRuntime.pm", "bin/vzlogger_control.pl"); Groups = @("Runtime", "Lifecycle"); Device = "targeted service flow when LoxBerry paths, locks, ownership, or service wiring changed"; Browser = "none" }
		@{ Patterns = @("bin/SmartMeterVZLoggerBridge.pm", "bin/SmartMeterVZLoggerHttp.pm", "bin/vzlogger_mqtt_bridge.pl"); Groups = @("Bridge"); Device = "targeted affected output or service flow"; Browser = "none unless rendered output state changed" }
		@{ Patterns = @("bin/SmartMeterVZLoggerObisStatus.pm", "webfrontend/htmlauth/obis_status.cgi"); Groups = @("Obis"); Device = "targeted OBIS status/discovery flow"; Browser = "changed OBIS workflow at Chrome primary sizes" }
		@{ Patterns = @("bin/SmartMeterWebSecurity.pm", "webfrontend/html/recovery.php", "webfrontend/htmlauth/htaccess"); Groups = @("WebSecurity"); Device = "targeted authenticated and negative flow"; Browser = "authenticated Chrome desktop smoke" }
		@{ Patterns = @("webfrontend/htmlauth/index.cgi", "webfrontend/htmlauth/help.cgi", "webfrontend/htmlauth/logfiles.cgi", "webfrontend/htmlauth/service_status.cgi", "webfrontend/htmlauth/show.cgi", "webfrontend/htmlauth/vzlogger_config.cgi", "webfrontend/htmlauth/vzlogger_live.cgi", "webfrontend/htmlauth/vzlogger_live_data.cgi"); Groups = @("Ui"); Device = "targeted executable CGI flow"; Browser = "authenticated Chrome desktop smoke; add primary mobile for changed UI behavior" }
		@{ Patterns = @("templates/*.html", "templates/**/*.html", "webfrontend/html/index.php", "webfrontend/htmlauth/*.css", "webfrontend/htmlauth/smartmeter-settings*.js", "webfrontend/htmlauth/smartmeter-ui.js", "webfrontend/htmlauth/smartmeter-vzlogger.js"); Groups = @("Ui"); Device = "installed rendering only when needed"; Browser = "assess impact: Chrome primary sizes for behavior, full matrix for layout/responsive/shared controls" }
		@{ Patterns = @("templates/vzlogger_live.html", "webfrontend/htmlauth/vzlogger_live.js", "webfrontend/htmlauth/vzlogger-live.css"); Groups = @("LiveUi"); Device = "installed live page when behavior changed"; Browser = "Chrome primary sizes; full matrix for layout or browser-sensitive changes" }
		@{ Patterns = @("preinstall.sh", "preroot.sh", "postinstall.sh", "postroot.sh", "preupgrade.sh", "postupgrade.sh", "cron/**", "dpkg/**", "uninstall/**", "sbin/**", "templates/systemd/**", "sudoers/**", "config/smartmeter.cfg"); Groups = @("Lifecycle"); Device = "only affected lifecycle scenarios using a local package"; Browser = "only affected installed UI flows" }
		@{ Patterns = @("plugin.cfg", "release.cfg", "prerelease.cfg", ".gitattributes", ".github/workflows/release-asset.yml", "icons/**", "tools/build-local.ps1", "tools/validate-release-metadata.pl"); Groups = @("Metadata"); Device = "none unless packaging or lifecycle behavior changed"; Browser = "none" }
		@{ Patterns = @("tools/deploy-test-device.ps1", "tools/TestDeviceFileTransfer.ps1", "tools/TestDeviceSettings.ps1", "tools/check-test-device.ps1", "tools/configure-test-device.ps1"); Groups = @("DeploymentTooling"); Device = "none; tooling is tested locally"; Browser = "none" }
		@{ Patterns = @("tools/test.ps1", "tools/check-perl-syntax.ps1", "tests/test-map.psd1", "tests/test_test_runner.ps1", ".github/workflows/syntax-check.yml", ".codex/environments/**"); Groups = @("Runner"); Device = "none"; Browser = "none" }
		@{ Patterns = @("webfrontend/htmlauth/vendor/chart.js/**"); Groups = @("Vendor"); Device = "none"; Browser = "live page only when the vendored runtime changed" }
	)

	RuntimeFallbackPatterns = @(
		"bin/**", "config/**", "sbin/**", "templates/**", "uninstall/**",
		"webfrontend/**", "tools/**", ".github/ci/**", "*.sh", "*.cfg", "sudoers/**"
	)
}
