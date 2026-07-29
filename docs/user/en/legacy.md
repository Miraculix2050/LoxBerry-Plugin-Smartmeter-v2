# Use Legacy

## When Legacy is useful

Legacy remains a supported fallback for existing installations and meter configurations not covered by vzLogger. Prefer vzLogger for new setups where possible.

Legacy and vzLogger retain separate saved settings. Switching does not change the other configuration. No Legacy removal date has been announced.

## Enable Legacy

1. Open **SmartMeter configuration (Legacy)**.
2. Switch **Active** on.
3. Select the detected reading head and a meter template or **Manual configuration**.
4. Enable **Read meters periodically** and select an interval when required.
5. Select the required HTTP, UDP, and MQTT outputs.
6. Save the page.

Saving active Legacy mode stops vzLogger and the bridge and restores the Legacy cron job. Disabling Legacy does not automatically activate vzLogger.

## Configure the meter

With a template selected, the disabled **Manual settings** area shows the values actually used. Your separately saved manual values remain intact.

A manual configuration can set protocol, baud rates, parity, handshake, data/stop bits, timeout, delay, and CRC. Use the meter manufacturer's values. Invalid general or meter values reject the complete save without partial changes.

## Read manually and clear cache

**Read meters manually** is available when Legacy is already saved as active and vzLogger is stopped. Periodic reading may remain disabled.

**Clear cache** removes only Legacy data, dump, and log files. Configuration locks and vzLogger runtime status remain intact.

## Legacy outputs

- **HTTP:** Always enabled. The displayed URL serves Legacy cached values.
- **UDP:** Sends values to every Miniserver configured in LoxBerry; port range `1–65535`.
- **MQTT:** Publishes through the LoxBerry MQTT Gateway.

Default base topic:

```text
smartmeter
```

Topic and payload:

```text
<base-topic>/<meter>/<value-name>
smartmeter/ABC123/Consumption_Total_OBIS_1.8.0
1234.567
```

Legacy MQTT messages use retain. The base topic must contain 1–256 characters and no control characters or MQTT wildcards `+` and `#`.
