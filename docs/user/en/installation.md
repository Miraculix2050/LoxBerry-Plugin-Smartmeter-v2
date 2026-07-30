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

A fresh installation enables the vzLogger desired state but has no configured meter, so vzLogger and the bridge initially remain stopped. The bridge is disabled; its prepared output defaults are MQTT timestamps on, HTTP cache off, and UDP off.

If the installation log says that `udevadm` could not run, disconnect and reconnect the USB reading head. Reboot LoxBerry only if the device path is still missing afterwards.

## Update

1. Open LoxBerry Plugin Management and start the offered SmartMeter v2 update, or install the official ZIP for the target version.
2. Check the installation log when it finishes.
3. Open the configuration page and verify the saved desired states and current service states.
4. Open live data and confirm current readings.

Version 2.1.0.0 preserves a valid generated vzLogger configuration, channel UUIDs, output keys, the Expert draft, bridge outputs, and recovery settings. Previous `vzlogger` and `none` modes migrate to the matching enabled or disabled desired state; the previous bridge switch is migrated independently.

An upgrade is blocked before file replacement when Legacy is still active, including older installations inferred as active Legacy. Stay on or reinstall 2.0.1.0, activate vzLogger there, and complete **Save and apply** successfully before retrying 2.1.0.0. Inactive Legacy settings are removed during an allowed upgrade and are not retained as a backup. No reboot is required.

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
