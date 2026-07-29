# Troubleshooting

Work through the advice for the visible symptom. Do not change several settings at once. Check the result after each step.

## Installation or update fails

1. Open the installation log in LoxBerry Plugin Management.
2. First find the plugin's final success or failure status. Generic LoxBerry warnings are not automatically plugin failures.
3. Check Internet access, free storage, and the LoxBerry package sources.
4. If installation of `vzlogger` or `mosquitto-clients` fails, resolve the package error first and run the installation again.

## Reading head or device path is missing

1. Check power, seating, and alignment of the reading head.
2. Disconnect the reading head briefly and reconnect it.
3. Reload the SmartMeter page and select **Detect devices again**.
4. Check whether the expected stable plugin path appears below `/dev/serial/smartmeter/`. Use it instead of `/dev/ttyUSB0`.

If no device is detected, first try the reading head on another USB port. A visible device path confirms only the USB device, not the correct protocol or installation on the meter.

## OBIS discovery finds no values

Check protocol, baud rate, parity, and reading-head position. Some meters transmit values only after activation at the meter. Automatic discovery is unavailable for OMS meters.

Discovery runs in the background. Wait for completion and open the result again. Detected identifiers are then stored, but only **Save and apply** adds selected channels to the active configuration.

## Save and apply fails

- **Invalid configuration:** Correct the highlighted field. Ports may be `1–65535`; QoS may only be `0` or `1`.
- **Action already running:** Wait for discovery, apply, or mode switching to finish. A shared lock protects changes.
- **Timeout or sudo error:** Open **Logs**, find the related action, and do not repeat it continuously.
- **Service remains stopped:** At least one active meter and a valid configuration are required. Apply deliberately stops services when the mode is inactive or no meter exists.

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

## Legacy polling returns no values

Check schedule, protocol, and reading head. **Read now** performs one poll; the log view shows its result. Legacy and vzLogger never run at the same time. Switching to Legacy stops vzLogger and the bridge in a controlled way.

If the issue remains, save the relevant log message without passwords or keys and include the plugin version, LoxBerry version, meter model, reading head, and selected protocol in a support request.
