# Advanced Features

## Custom meter with JSONC

Select **Custom (JSON)** only when the standard form cannot represent your protocol or device. The editor expects exactly one complete vzLogger meter object:

```jsonc
{
  // Example for a protocol supported by vzLogger
  "protocol": "s0",
  "device": "/dev/serial/smartmeter/example",
  "channels": [
    { "uuid": "11111111-1111-4111-8111-111111111111", "api": "null" }
  ]
}
```

Root sections such as `meters`, `mqtt`, `local`, `push`, or `retry` are not allowed here. Comments are supported and source up to 64 KiB is stored unchanged. For runtime generation, the plugin supplies only missing UUID/`api` values in existing channels without rewriting the JSONC text.

An invalid object remains saved for correction and receives a warning. It is omitted from the newly generated runtime configuration. Use the external **Parameter documentation** link for current vzLogger syntax.

## Expert Mode

Expert Mode edits a separate persistent `vzlogger_expert.conf` draft.

1. First generate a valid `vzlogger.conf` at least once.
2. Enable **Expert Mode**.
3. Open **Edit vzLogger configuration**.
4. Edit the complete JSON and select **Save & close**.

The editor shows unmasked credentials and is therefore available only in the authenticated frontend. A valid file becomes the runtime configuration without automatically restarting the service. An invalid draft is retained while the last valid runtime file remains active.

While Expert Mode is active, standard vzLogger fields are read-only. Bridge settings and native debug logging remain separately editable. New or unknown channel UUIDs are not automatically published by the bridge.

Disabling Expert Mode does not delete the draft. **Reinitialize from current vzlogger.conf** is the only action that deliberately overwrites it after confirmation.

## Service control

The page has separate panels for `vzlogger` and `smartmeter-v2-vzlogger-bridge`.

- **Start** and **Restart** validate and use the saved valid configuration. They do not save other open form values.
- **Stop** remains available for a running service even when configuration is invalid.
- Status refreshes every ten seconds while the page is visible.
- A manual Stop lasts until the next reboot. To disable a service persistently, switch off its activation in the plugin UI and use **Save and apply**.

## Loxone service recovery

Recovery allows a Loxone Miniserver to start an expected service in `failed` state or restart a service that is still active but stalled. It never starts an intentionally inactive, disabled, or unconfigured service.

1. Open **Loxone service recovery**.
2. Generate a random token and copy it immediately; it is shown only once.
3. Enable the source-IP restriction where possible.
4. Save the recovery settings.
5. Copy the displayed base address into one virtual output and the fields for `vzlogger`, `bridge`, or `all` into virtual output commands.

Every command uses `POST`, an empty body, and the `X-Smartmeter-Recovery-Token` header. Do not put a LoxBerry user or password in the URL. If the token is lost, generate a new one and update Loxone; the previous token stops working immediately.

Recovery is not a replacement for network access control. Use HTTPS when the Miniserver supports it and keep the endpoint inside the trusted LAN.

## Logs and diagnostics

Bridge, service control, web interface, and diagnostics appear under **SmartMeter v2 (Plugin Log)** in the LoxBerry log manager and use its shared plugin log level.

For a bridge problem:

1. Temporarily set the plugin log level to **Debug**.
2. Reproduce the problem.
3. Open **Show log** or create a **Debug log**.
4. Restore the previous log level afterwards.

The debug log contains package, service, validation, mapping, cache, and bounded MQTT diagnostics. Passwords and private keys are masked. The separate native vzLogger log `vzlogger-native.log` is written only while the vzLogger debug option is active.
