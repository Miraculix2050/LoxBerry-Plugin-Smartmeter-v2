# Plugin Lifecycle Test Expectations

- **Audience:** Developers, testers, maintainers, and AI agents
- **Status:** Current acceptance contract for 2.1.0.0
- **Authority:** Normative lifecycle verification

## Fresh Install

- Installation completes without requesting a reboot.
- `VZLOGGER.ENABLED=1` and `VZLOGGER.BRIDGEENABLED=0` are stored.
- No meter is configured, so vzLogger and the bridge remain stopped and no service override is installed.
- Connected USB I/R heads are available below `/dev/serial/smartmeter/`.
- Optional logs and debug logs are disabled.

## Upgrade From 2.0.1.x

- `MAIN.IMPLEMENTATION=vzlogger` migrates to `VZLOGGER.ENABLED=1`.
- `MAIN.IMPLEMENTATION=none` migrates to `VZLOGGER.ENABLED=0`.
- `MAIN.READ` migrates to `VZLOGGER.BRIDGEENABLED`.
- `MAIN.IMPLEMENTATION=legacy`, or a missing mode with `MAIN.READ=1`, aborts before files or configuration are changed and directs the user to migrate with the latest supported 2.0.1.x Legacy maintenance release (currently 2.0.1.1).
- A direct update from `Smartmeter-V2.0.0.10` with active Legacy (`MAIN.READ=1`) is blocked unchanged. Its supported route is `Smartmeter-V2.0.0.10` to 2.0.1.1, successful vzLogger Save/Apply, then 2.1.0.0. An inactive `Smartmeter-V2.0.0.10` configuration (`MAIN.READ=0`) may update directly and remains disabled.
- Allowed upgrades remove `MAIN.IMPLEMENTATION`, `MAIN.READ`, `MAIN.CRON`, `MAIN.SENDMQTT`, every `LEGACY_*` value, exact installed Legacy files including the obsolete `show.cgi`, per-reader Legacy logs/state, fetch runtime files, and obsolete cron links.
- A per-reader `.data` cache is retained only when bridge and HTTP cache are both enabled. Current `vzLogger_*`, `vzlogger_*`, recovery, and unrelated runtime files remain intact. Cleanup is idempotent; an actual deletion failure fails the upgrade.
- `libdevice-serialport-perl` is no longer requested because it served only Legacy code. An existing system installation is retained rather than purged.
- Generated vzLogger configuration, channel UUIDs, output keys, Expert draft, bridge outputs, recovery settings, and user configuration remain intact.
- Repeating the migration and cleanup produces the same result.

## Apply And Temporary Service Actions

- Enabled, valid, metered Apply generates, validates, atomically promotes, installs the override, and starts the requested services.
- Disabled Apply stops and disables vzLogger and bridge and removes the override without deleting the last valid configuration.
- Enabled meterless Apply is accepted but leaves both services stopped and removes the override.
- Failed activation restores `VZLOGGER.ENABLED=0` and leaves both services stopped.
- Bridge operation additionally requires `VZLOGGER.BRIDGEENABLED=1`, valid applied configuration, and a suitable MQTT source.
- Start and Restart require a saved enabled and startable state. Stop is always available. These actions never change either persisted activation value.
- Concurrent configuration or service actions are rejected without partial writes.
- Independent OBIS-discovery and bridge-fallback background processes release the parent action lock before continuing and cannot block later configuration or service actions.

## Recovery

- The POST-only recovery targets remain `vzlogger`, `bridge`, and `all`.
- Recovery respects `VZLOGGER.ENABLED`, `VZLOGGER.BRIDGEENABLED`, applied configuration validity, and service dependencies.
- It never starts an administratively disabled, optional-disabled, unconfigured, or manually stopped inactive unit.

## Uninstall

- Plugin-owned services, drop-ins, runtime/cache artifacts, udev rules, repository/key markers, and packages are removed.
- Pre-existing packages, repositories, and keys without ownership markers are retained.
- Any obsolete SmartMeter Legacy cron references left from older installations are removed safely.
