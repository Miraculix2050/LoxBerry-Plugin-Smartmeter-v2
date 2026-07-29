# Installation, Update, and Uninstall

## Requirements

- LoxBerry 4.0.0 or newer. This is the installation gate, not evidence for every newer platform; check the [support matrix](../../support-matrix.en.md).
- An optical I/R reading head that the target exposes below `/dev/serial/smartmeter/`.
- Access to LoxBerry Plugin Management and the installation log.
- For vzLogger, a reachable MQTT broker. The LoxBerry MQTT settings are normally inherited.

The plugin installs `vzlogger` and `mosquitto-clients` through LoxBerry's normal package list. It does not bundle vzLogger.

## Prepare the reading head and meter

1. Check the meter documentation to determine whether it transmits SML, D0, or OMS.
2. Mount the reading head over the optical interface as specified by its manufacturer. Incorrect alignment can produce empty or incomplete telegrams.
3. Connect the reading head to LoxBerry.
4. After installation, its stable device path must appear below `/dev/serial/smartmeter/`. The plugin UI shows detected paths.

Templates provide useful starting values, not a compatibility promise. See [Known limitations](../../known-limitations.en.md) for confirmed hardware evidence.

## Install a new copy

1. Open the required version under [GitHub Releases](https://github.com/Miraculix2050/LoxBerry-Plugin-Smartmeter-v2/releases).
2. Download the official `Smartmeter-V<version>.zip`. Do not use an automatic GitHub source-code archive.
3. Open LoxBerry Plugin Management and install that ZIP as a plugin.
4. Wait for plugin and additional-package installation to finish.
5. Check the final success messages in the installation log. Generic LoxBerry warnings are not automatically plugin failures.
6. Open SmartMeter v2. A reboot is normally unnecessary.

A fresh installation selects vzLogger mode but has no configured meter, so vzLogger and the bridge initially remain stopped. The bridge is disabled; its prepared output defaults are MQTT timestamps on, HTTP cache off, and UDP off.

If the installation log says that `udevadm` could not run, disconnect and reconnect the USB reading head. Reboot LoxBerry only if the device path is still missing afterwards.

## Update

1. Open LoxBerry Plugin Management and start the offered SmartMeter v2 update, or install the official ZIP for the target version.
2. Check the installation log when it finishes.
3. Open both configuration pages and verify the active mode and service states.
4. Open live data, or perform a manual Legacy reading.

An update preserves the saved `vzlogger`, `legacy`, or `none` mode, a valid generated vzLogger configuration, the expert draft, Legacy settings, and existing output selections. Older installations retain their previous bridge behavior: bridge MQTT initially remains off and HTTP cache remains on until you change them.

No reboot is required. For the Legacy **At system startup** interval, one reading runs immediately after a successful update.

## Uninstall

Uninstall SmartMeter v2 through LoxBerry Plugin Management. This removes plugin-owned configuration, services, drop-ins, Udev rules, runtime/cache files, and plugin directories.

The plugin removes `vzlogger`, its apt source, and key only when ownership markers prove that SmartMeter v2 introduced them. Installations that existed before the plugin and have no such markers are retained.

Manually save any configuration values you still need before uninstalling. The plugin provides no restore function after removal.

## Network security

LoxBerry and SmartMeter v2 are intended only for a trusted LAN. Do not expose these endpoints to the public Internet:

- LoxBerry web interface
- vzLogger HTTP service, port `18080` by default
- SmartMeter HTTP cache
- Loxone recovery endpoint

The vzLogger service and HTTP cache are unauthenticated. Disabling the index is not access control. Meter readings can reveal presence and activity. Prefer HTTPS and a source-IP allow-list for recovery, and never use router port forwarding or a public reverse proxy for these endpoints.
