# Use Readings and Outputs

[← Configure vzLogger](configuration.md) · [Back to the overview](../../User-Guide.en.md) · [Next: Advanced features →](advanced.md)

## Understand the data flow

vzLogger reads meters and publishes readings by MQTT below:

```text
<base-topic>/vzlogger
```

For every channel enabled through **Output in SmartMeter**, the bridge subscribes to exactly one applied path:

```text
<base-topic>/vzlogger/chnN/agg   with effective aggregation
<base-topic>/vzlogger/chnN/raw   otherwise
```

The bridge never reads the serial device itself. MQTT timestamps are published immediately; HTTP cache and UDP use the shared update cycle.

## Display live data

**Open live data (JSON)** shows the vzLogger HTTP endpoint. **Live data as web page** shows a localized table and chart.

The page refreshes every two seconds by default. You can also select 10 or 30 seconds, or 1, 2, or 5 minutes. Collection pauses by default while the tab is hidden.

History is stored only in IndexedDB in the current browser profile, not on LoxBerry. Raw values remain for 15 minutes and compacted values extend to seven days. Other browsers or profiles have separate histories. **Clear stored history** affects only this browser.

Electrical SML energy counters are converted from Wh to kWh for display. The vzLogger raw value remains available in the tooltip.

## Bridge MQTT

Enable **Bridge service enabled** and **Publish Unix and Loxone timestamps by MQTT**. The bridge inherits broker, authentication, TLS, QoS, and retain from the applied vzLogger configuration and publishes to:

```text
<base-topic>/bridge
```

Example:

```json
{"A106Q3RX":{"Last_UpdateUnix":1785264660,"Last_UpdateLoxEpoche":554503860}}
```

`Last_UpdateUnix` is UTC. `Last_UpdateLoxEpoche` is converted for local Loxone `<v.u>` display and can move backwards at the autumn transition. This output requires vzLogger source timestamps. It contains timestamps, not every channel value; vzLogger continues to publish channel values below its `chnN` topics.

The LoxBerry MQTT Gateway can expand the JSON into individual virtual inputs. Use `<base-topic>/bridge` and the JSON paths for the required serial number and property.

## HTTP cache

Enable the bridge and **Update HTTP cache**. The **Open HTTP cache** link leads to:

```text
http://<loxberry>/plugins/<plugin-folder>/index.php
```

Example response:

```text
A106Q3RX:Last_Update:2026-07-29 12:34:56
A106Q3RX:Last_UpdateLoxEpoche:554503860
A106Q3RX:Consumption_Total_OBIS_1.8.0:1234.567
#EOF
```

The endpoint reads RAM-backed `.data` files below `/var/run/shm/<plugin-folder>/`. When cache output is off, the bridge removes these files and the endpoint returns `# HTTP cache disabled` followed by `#EOF`.

The cache is unauthenticated. Use it only inside the trusted LAN.

## UDP to Loxone

Enable the bridge and **Send UDP**, enter a destination port from `1` through `65535`, and configure at least one Miniserver in LoxBerry. On each selected update cycle, the bridge sends one datagram per meter to every configured Miniserver.

Example:

```text
A106Q3RX:Last_Update:2026-07-29 12:34:56; A106Q3RX:Last_UpdateLoxEpoche:554503860; A106Q3RX:Consumption_Total_OBIS_1.8.0:1234.567
```

Create a virtual UDP input with the same port in Loxone Config and parse the required `serial:output-key:value` segments. HTTP and UDP use the same values and order, but UDP does not read cache files.

## Direct vzLogger targets

Independently of the SmartMeter bridge, a channel can be sent directly to an API supported by vzLogger. Select the target in the channel's advanced settings and complete its required fields. Use credentials with minimal permissions and HTTPS where possible.

### Volkszaehler

Minimal selection:

```text
API: volkszaehler
middleware: https://vz.example.lan/middleware.php
```

The channel UUID identifies the Volkszaehler channel. `duplicates` can temporarily suppress repeated identical values.

### InfluxDB

Minimal InfluxDB 2 selection:

```text
API: influxdb
version: 2
host: https://influx.example.lan:8086
database/bucket: smartmeter
organization: home
token: <token with write access to this bucket>
```

Measurement, tags, batch/buffer, and TLS verification can also be configured. Disable certificate verification only when specifically required inside the trusted LAN.

### MySmartGrid

Minimal selection:

```text
API: mysmartgrid
middleware: https://api.example.lan/
secretKey: <registration key>
device: <device identifier>
type: device or sensor
```

The `name` field is the MySmartGrid registration name, not a general display name.

## Order and calculated values

HTTP and UDP begin with `Last_Update` and `Last_UpdateLoxEpoche`. Active output keys then follow in `chnN` order, followed by additional values alphabetically.

When a matching instantaneous-power reading is absent, the bridge can calculate import or export power from two different energy-counter readings. A directional power value suppresses its matching calculation; a signed total-power value suppresses both.

[← Configure vzLogger](configuration.md) · [Back to the overview](../../User-Guide.en.md) · [Next: Advanced features →](advanced.md)
