# Configure vzLogger

## Set the desired service state

1. Open the vzLogger page.
2. Switch **Active** on.
3. Configure at least one active meter.
4. Apply the state with **Save and apply**.

The switch stores the desired vzLogger state only when you use **Save and apply**. Start, Stop, and Restart are temporary service actions and do not change it. A valid existing `vzlogger.conf` remains available while vzLogger is disabled and is reused on later reactivation.

## Add a reading head

1. Connect the reading head.
2. Select **Rescan for I/R reading heads**.
3. Open the new panel showing its device path and serial identifier.
4. Assign a readable name if required.
5. Select the protocol:
   - **SML** for binary SML telegrams.
   - **D0** for IEC 62056-21/D0 telegrams.
   - **OMS** for OMS/M-Bus; the installed vzLogger version must support OMS.
   - **Custom (JSON)** for other vzLogger protocols or network devices.

A new reading head remains marked **New / unsaved** until applied. A reading head without a protocol does not generate a meter.

## Use a template

**Initialize from template** is available for SML and D0. A template sets only the known serial starting values and, for D0, the read timeout. Name, activation, device, intervals, sequences, and channels remain unchanged.

Templates are based on project experience. Check their values against your meter documentation. Templates marked `limited` may require sequences that the standard form cannot represent; use Custom JSONC when vzLogger supports the required behavior.

## Basic meter settings

- **Meter enabled:** Includes the meter in the generated configuration.
- **Skip errors (`allowskip`):** Recommended so one unavailable meter does not terminate other meters.
- **Interval:** Access delay for actively polled meters; `-1` is usual for meters that push data.
- **Aggregation time (`aggtime`):** `-1` disables aggregation. A positive value collects readings for channel processing.
- **Fixed aggregation intervals:** Effective only with a positive aggregation time.

Empty optional fields are omitted from `vzlogger.conf`. The standard form always uses the detected local device path. Use custom JSONC for a TCP-backed meter.

## Save for the first time

Select **Save and apply** before starting OBIS discovery. The action saves form values, generates and validates the configuration, and establishes the requested service state:

- Enabled vzLogger with at least one active meter installs the plugin override, enables vzLogger, and restarts it.
- An active bridge is installed, enabled, and started.
- A disabled bridge is stopped and removed from autostart.
- A disabled or meterless configuration stops vzLogger and the bridge and removes the plugin override.

A failure never replaces the last coherent valid runtime configuration. Submitted values may remain saved for correction.

## Discover OBIS channels

1. Open the required SML, D0, or OMS meter.
2. Select **Read OBIS channels**.
3. Wait for the result or use **Cancel search**.
4. Review newly found channels.

Discovery uses the meter values currently shown in the browser, temporarily stops vzLogger, and restores the previous service state afterwards. It continues in the background if you reload or leave the page. The job stores detected identifiers. You decide which channels become active in `vzlogger.conf` and the bridge when you next use **Save and apply**.

If discovery finds nothing, check the protocol, reading-head alignment, baud rate/serial mode, and discovery log.

## Select channels

Each channel has a UUID and OBIS identifier. You can:

- enable or disable the channel;
- assign a readable display name;
- select a meter-provided storage index `0–254` for SML/D0;
- select `none`, `avg`, `max`, or `sum` when meter aggregation is active;
- configure a direct vzLogger API target;
- enable **Output in SmartMeter**.

**Output in SmartMeter** makes the channel available to enabled bridge outputs. HTTP cache and UDP can be enabled independently. The output key is the only name used through cache and UDP and must be unique per reading head without regard to case.

Manually added channels can be staged for removal. Discovered channels are normally disabled so that a later discovery can recognize them again. Staged changes become permanent only with **Save and apply**.

## Validate or apply

- **Validate config** generates a temporary draft. Saved files and services remain unchanged.
- **Save and apply** saves, generates, validates, and applies the configuration.

Both actions have a 60-second time limit. If another configuration or service action is active, the new action is rejected without partial changes. Start and Restart use only the already saved valid configuration; Stop remains available for a running service.

## Remove a meter

**Remove meter configuration** initially hides a meter only in the current browser draft. **Save and apply** permanently removes its saved settings and plugin-owned artifacts. A removed reading head that remains connected stays hidden during ordinary page loads; a new reading-head scan recreates it with default settings.
