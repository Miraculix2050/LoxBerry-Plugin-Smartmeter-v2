# Technical reference

[← Troubleshooting](troubleshooting.md) · [Back to the overview](../../User-Guide.en.md)

This page collects details for diagnosis, backup, and advanced integration. [Configuration](configuration.md) and [Outputs](outputs.md) are sufficient for normal setup.

## Services and desired states

| Component | Purpose | When active |
|---|---|---|
| `vzlogger` | Reads meters and publishes readings by MQTT | `VZLOGGER.ENABLED=1`, valid configuration, at least one active meter |
| `smartmeter-v2-vzlogger-bridge` | Produces bridge MQTT, HTTP cache, and UDP | Bridge enabled and a usable applied output exists |

Disabled or meterless state stops the related services without deleting a valid generated configuration. Manual Start, Stop, and Restart do not change the saved desired states.

## Configuration and runtime paths

`<plugin-folder>` is the installed plugin folder and may differ from a repository name.

| Path | Meaning | Type |
|---|---|---|
| LoxBerry plugin configuration `smartmeter.cfg` | Desired states, meter settings, and output defaults | authoritative user setting |
| LoxBerry plugin configuration `vzlogger.conf` | Applied vzLogger runtime configuration | generated and retained during updates |
| `vzlogger_expert.conf` in the plugin configuration directory | Separate Expert Mode draft | authoritative user setting in Expert Mode |
| `vzlogger_meter_<serial>.jsonc` | Custom meter object for one reading head | authoritative user setting |
| `vzlogger_channel_definitions.json` | Complete UI model of active and inactive channels | authoritative channel model |
| `vzlogger_channels.json` | Active output channels used by the bridge | generated from the applied configuration |
| `vzlogger_user_channel_uuids_<serial>.json` | Stable UUID assignment for custom channels | persistent identity mapping |
| `obis_channels_<serial>.cache` | Most recently discovered OBIS identifiers | persistent, reproducible discovery state |
| `smartmeter_recovery.json` | Recovery settings and hashed token | authoritative user setting |
| `/var/run/shm/<plugin-folder>/` | Volatile logs, running discovery jobs, live cache, and HTTP cache | runtime data |
| `/var/run/shm/<plugin-folder>/vzlogger_config.lock` | Shared lock for mutating actions | runtime file |

Files in the RAM directory disappear on restart. Persistent configuration resides in the LoxBerry configuration directory and survives normal updates.

## MQTT topics

vzLogger publishes active channels below `<base-topic>/vzlogger`. For each enabled output, the bridge subscribes to exactly `chnN/raw`, or `chnN/agg` when aggregation is effective.

The optional bridge output publishes one combined timestamp object below `<base-topic>/bridge`. QoS may be `0` or `1`; retain is inherited from the applied vzLogger configuration. Topic names contain 1–256 characters and no control characters or wildcards `+` and `#`.

## Data formats

HTTP returns one line per value and ends with `#EOF`:

```text
meter-1:Power:431.2
meter-1:Energy Import:12345.678
#EOF
```

UDP sends the same entries in the same order, separated by `; `:

```text
meter-1:Power:431.2; meter-1:Energy Import:12345.678
```

Bridge MQTT contains `Last_UpdateUnix` and `Last_UpdateLoxEpoche` for each serial number. Unix time remains UTC. The Loxone epoch uses the local timezone at the measurement time and can move backwards at the transition from summer to winter time.

Output keys may contain 1–64 characters. `:` and `;` are reserved delimiters. Keys must be unique per reading head without regard to case.

## Limits and defaults

| Setting | Contract |
|---|---|
| MQTT broker, vzLogger HTTP, and UDP destination ports | `1–65535` |
| MQTT QoS | `0` or `1` |
| MQTT topic | 1–256 characters without control characters, `+`, or `#` |
| Live-data interval | Default 2 seconds; selectable up to 5 minutes |
| Bridge update cycle for HTTP cache and UDP | 5, 10, or 30 seconds; 1, 3, 5, 10, 15, 30, or 60 minutes |
| Recovery | POST only, token required, optional IP filter and cooldown |

A fresh installation prepares bridge MQTT as on and HTTP cache and UDP as off; they take effect only after the bridge is enabled. Upgrades preserve existing selections.

## Saving, staging, and recovery

The UI initially holds edits in the browser. **Save and apply** validates the complete draft, creates the related files in a protected staging directory, and promotes them atomically. On failure, the last valid runtime configuration remains intact.

OBIS discovery stores detected identifiers independently of whether the page remains open. Only a later apply selects active channels from them. Meter removal likewise becomes persistent only on apply and removes only mappings and runtime artifacts owned by that meter.

For a manual backup, prefer LoxBerry's backup function and include the SmartMeter plugin configuration. If you back up individual files, capture the files marked authoritative or persistent above as one set. Do not copy `/var/run/shm` files as a configuration backup. Copying individual files back is not a supported plugin restore workflow; use a complete LoxBerry backup that matches the installation.

## Logs and privacy

Plugin actions use LoxBerry logs. Repeated identical bridge warnings are rate-limited; native vzLogger logging can be enabled separately. Passwords, private keys, and tokens must not be included in support attachments.

The local vzLogger HTTP service, HTTP cache, and recovery endpoint are not intended for public networks. A disabled `local.index` is not access control. Do not use router port forwarding or a public reverse proxy.

[← Troubleshooting](troubleshooting.md) · [Back to the overview](../../User-Guide.en.md)
