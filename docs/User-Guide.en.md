# SmartMeter v2 User Guide

- **Audience:** LoxBerry users, including users without Linux or vzLogger experience
- **Status:** Current implemented development state on `master`

## Overview

SmartMeter v2 reads meters through an optical I/R reading head using vzLogger. vzLogger publishes readings by MQTT. The optional SmartMeter bridge can produce MQTT timestamps, an HTTP cache, and UDP data for Loxone.

> **Security:** Use LoxBerry, the vzLogger HTTP service, the SmartMeter HTTP cache, and the recovery endpoint only inside a trusted LAN. Never expose these services through router port forwarding or a public reverse proxy.

## Quick start

1. Check the [requirements and known limitations](user/en/installation.md#requirements).
2. Download the official ZIP for the required version from [GitHub Releases](https://github.com/Miraculix2050/LoxBerry-Plugin-Smartmeter-v2/releases) and install it through LoxBerry Plugin Management.
3. Connect the reading head and open **SmartMeter v2 → SmartMeter configuration (vzLogger)**.
4. Enable vzLogger and select **Rescan for I/R reading heads**.
5. Open the reading head, select SML, D0, or OMS, and initialize it from a suitable template when needed.
6. Select **Save and apply**. OBIS discovery can access the reading head only afterwards.
7. Start **Read OBIS channels**, enable the required channels, and select **Output in SmartMeter** when needed.
8. Enable the required bridge outputs and select **Save and apply** again.
9. Open **Live data as web page** and confirm that current values appear.

See [Configuration](user/en/configuration.md) for the complete workflow.

## Documentation by task

- [Installation, update, and uninstall](user/en/installation.md)
- [Configure vzLogger](user/en/configuration.md)
- [Use readings and outputs](user/en/outputs.md)
- [Advanced features](user/en/advanced.md)
- [Troubleshooting](user/en/troubleshooting.md)
- [Technical reference](user/en/reference.md)
- [Known limitations](known-limitations.en.md)
- [Tested support matrix](support-matrix.en.md)

## Terms in brief

- **I/R reading head:** Optical adapter mounted on the meter. LoxBerry exposes detected devices below `/dev/serial/smartmeter/`.
- **SML, D0, OMS:** Protocols used by different meters to transmit readings.
- **OBIS:** Standard identifier for a reading, for example `1-0:1.8.0` for imported energy.
- **vzLogger:** External program that reads the meter and publishes readings.
- **SmartMeter bridge:** Optional plugin service that processes selected vzLogger MQTT values for MQTT timestamps, HTTP cache, and UDP.
- **Channel:** Configuration of one meter value.
