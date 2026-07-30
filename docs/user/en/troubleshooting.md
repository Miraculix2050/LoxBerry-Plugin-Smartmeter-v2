# Troubleshooting

[← Advanced features](advanced.md) · [Back to the overview](../../User-Guide.en.md) · [Next: Technical reference →](reference.md)

Work through the advice for the visible symptom. Do not change several settings at once. Check the result after each step.

## Installation or update fails

1. Open the installation log in LoxBerry Plugin Management.
2. First find the plugin's final success or failure status. Generic LoxBerry warnings are not automatically plugin failures.
3. Check Internet access, free storage, and the LoxBerry package sources.
4. If installation of `vzlogger`, `mosquitto-clients`, or `libdevice-serialport-perl` fails, check the Internet connection and access to the Volkszaehler project's Cloudsmith repository. Resolve the package error first and run the installation again.

## Reading head or device path is missing

1. Check power, seating, and alignment of the reading head.
2. Disconnect the reading head briefly and reconnect it.
3. Reload the SmartMeter page and select **Rescan for I/R reading heads**.
4. Check whether the expected stable plugin path appears below `/dev/serial/smartmeter/`. Use it instead of `/dev/ttyUSB0`.

If no device is detected, first try the reading head on another USB port. A visible device path confirms only the USB device, not the correct protocol or installation on the meter.

## OBIS discovery finds no values

Check protocol, baud rate, parity, and reading-head position. Some meters transmit values only after activation at the meter. OBIS discovery supports OMS only when the installed vzLogger version provides OMS support. If the UI reports that OMS is unsupported, discovery, validation, and apply are disabled for that meter.

Discovery runs in the background. Wait for completion and open the result again. Detected identifiers are then stored, but only **Save and apply** adds selected channels to the active configuration.

## Save and apply fails

- **Invalid configuration:** Correct the highlighted field. Ports may be `1–65535`; QoS may only be `0` or `1`.
- **Action already running:** Wait for discovery, apply, or a service action to finish. A shared lock protects changes.
- **Timeout or sudo error:** Open **Logs**, find the related action, and do not repeat it continuously.
- **Service remains stopped:** Saved activation, at least one active meter, and a valid configuration are required. Apply deliberately stops services when vzLogger is disabled or no meter exists.

## vzLogger or bridge is not running

Open **Services** and then **Logs**. Check the latest status first and then `vzlogger-native.log` if native debug logging was deliberately enabled.

The bridge is optional. It remains stopped when disabled, when no active SmartMeter output channel exists, or when the applied source is unusable. Use the switch in the SmartMeter UI to disable it; do not disable units manually with `systemctl`.

## MQTT or TLS does not work

Check broker name, port, credentials, and base topic. The topic must not contain `+` or `#`. With TLS, the CA file, certificate, and key must match and be readable by the service. Secrets are masked in the UI and logs.

Before enabling bridge output, verify that vzLogger publishes values below `<base-topic>/vzlogger`. Bridge timestamps appear separately below `<base-topic>/bridge`.

## Live data stays empty or slow

Live data requires a running, validly configured vzLogger instance. The default interval is two seconds; local chart settings offer intervals up to five minutes. After failures, the page temporarily increases the interval.

Check that the selected channel is active and MQTT data arrives. Browsers may additionally throttle a hidden tab.

## HTTP cache or UDP produces no output

Enable the bridge first and then the required output. Enable **Output in SmartMeter** for at least one channel. HTTP cache and UDP are independent; an active cache does not automatically enable UDP.

For UDP, the destination and port must be reachable. The port may be `1–65535`. The HTTP endpoint explicitly reports when the cache is disabled.

## Expert Mode cannot be applied

The draft must contain valid JSONC and satisfy the complete schema. Check the displayed validation and the logs. **Reinitialize from current vzlogger.conf** overwrites the draft only after confirmation; use it only when the previous draft is no longer needed.

## Recovery request is rejected

The recovery endpoint accepts only `POST` with the displayed token. It starts only a configured, active or recoverable service and does not install or enable units. Check method, token header, empty body, and target path. Never send the token across the public Internet.

## Upgrade to 2.1.0.0 is blocked

The upgrade stops before replacing files when Legacy is still active or an older configuration is recognized as active Legacy. Stay on or reinstall the latest supported 2.0.1.x Legacy maintenance release (currently 2.0.1.1). Activate vzLogger and complete **Save and apply** successfully. Then retry the upgrade.

If the issue remains, open a request in [GitHub Issues](https://github.com/Miraculix2050/LoxBerry-Plugin-Smartmeter-v2/issues). Include the plugin version, LoxBerry version, meter model, reading head, selected protocol, and relevant log message. Remove MQTT passwords, recovery tokens, private keys, complete certificates, and other private device data first.

[← Advanced features](advanced.md) · [Back to the overview](../../User-Guide.en.md) · [Next: Technical reference →](reference.md)
