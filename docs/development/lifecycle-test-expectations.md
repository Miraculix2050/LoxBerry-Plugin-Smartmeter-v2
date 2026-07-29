# Plugin Lifecycle Test Expectations

- **Audience:** Developers, testers, maintainers, and AI agents
- **Status:** Current acceptance contract
- **Authority:** Normative lifecycle verification

This document defines expected behavior for SmartMeter v2 plugin lifecycle operations. It is intentionally independent from a specific implementation plan and applies to fresh installation, installation over an existing version, and uninstall behavior.

## Uninstall

Precondition:

- SmartMeter v2 is installed.

Expected:

- Uninstall completes successfully.
- All plugin-owned folders and files are removed.
- Plugin-owned services are stopped and removed.
- The `vzlogger` package installed for SmartMeter v2 is removed.
- The vzLogger apt source and keyring introduced by SmartMeter v2 are removed.
- A pre-existing `vzlogger` package, apt source, or keyring without a plugin ownership marker is retained.

## Fresh Install

Precondition:

- No previous SmartMeter v2 plugin installation exists.

Expected:

- Installation completes successfully.
- The active implementation is `vzlogger`.
- Connected USB I/R heads are available below `/dev/serial/smartmeter/` before the first reboot.
- Installation does not request a reboot.
- The original LoxBerry 4.0.0 `LBPHTMLAUTH` environment name and a missing
  `LBPSBIN` alias are handled without fixed installation-root paths; the
  privileged helpers are installed root-owned in the derived plugin `sbin`.
- The MQTT bridge is disabled.
- All optional logs and debug logs are disabled.

## Install Over Existing Version

Precondition:

- A previous SmartMeter v2 plugin installation exists.

Expected:

- Installation completes successfully.
- The active implementation follows the previous configuration:
  - previous `vzlogger` remains `vzlogger`;
  - previous `legacy` remains `legacy`;
  - previous `none` remains `none`.
- An active Legacy configuration with the reboot polling interval is restored and receives one immediate reading without rebooting.

## Implementation Switching

Precondition:

- A generated and valid plugin-owned `vzlogger.conf` exists.

Expected:

- Activating Legacy stops vzLogger but does not overwrite the generated configuration.
- Deactivating either implementation without activating the other stops the corresponding runtime but does not regenerate `vzlogger.conf`.
- Reactivating vzLogger validates and applies the existing generated configuration without migrating the current Legacy meter settings.
- Legacy meter settings are migrated only when no valid generated vzLogger configuration exists.
- Saving while vzLogger is already active remains an explicit request to regenerate and apply its configuration.
- Concurrent configuration or service actions are rejected without partial writes.
- Failed generation, validation, promotion, override installation, or service restart returns a non-zero control result and preserves the last valid generated runtime files.
- Runtime, log, generated configuration, and serial-device permissions use only the existing `loxberry` and `_vzlogger` identities and do not require world-writable modes.
- Existing Legacy meter selection and manual serial settings are copied once into isolated `LEGACY_*` keys.
- Saving and activating vzLogger does not change the isolated Legacy meter settings.
- Reactivating Legacy restores the same selected preset or manual protocol and serial settings in both the UI and polling runtime.
