# Known Issues And Compatibility Limitations

- **Audience:** SmartMeter v2 users, administrators, and maintainers
- **Status:** Current confirmed limitations
- **Authority:** Normative for compatibility and security claims

This document tracks confirmed user-visible issues and compatibility limitations. It is not an implementation backlog. A limitation remains current until matching evidence supports narrowing or removing it.

Maintainer actions and evidence-expansion work are tracked separately in
[Compatibility Follow-up](https://github.com/Miraculix2050/LoxBerry-Plugin-Smartmeter-v2/blob/master/docs/development/compatibility-follow-up.md).

## Limited Target-Platform Coverage

Confirmed coverage:

- LoxBerry 4.0.0.13
- Debian 13/trixie
- arm64
- vzLogger 0.8.9 from the configured Cloudsmith repository
- Upgrade, disable/reactivate, uninstall, fresh install, service operation, SML/MQTT data flow, calculated power, HTTP cache, and UDP delivery were verified with SmartMeter v2 2.0.0.32.

Limitation:

- Other LoxBerry, Debian, or Raspberry Pi OS versions and other CPU architectures have not been tested.
- Repository availability and root-hook behavior outside Debian 13/trixie arm64 are not confirmed.

Impact:

- Compatibility outside the confirmed platform cannot be promised from the available test evidence.

## Legacy Web Security Remains Frozen

The modern vzLogger administration requires POST plus a user-bound CSRF token and escapes persisted configuration values in their HTML context. The functionally frozen Legacy administration does not receive this cross-cutting retrofit and retains its existing CSRF exposure. Keep the complete LoxBerry installation inside a trusted LAN, do not expose its web interface to the Internet, and prefer the vzLogger implementation for actively maintained security behavior.

## Meter-Template Coverage Requires Representative Hardware

Confirmed coverage:

- One connected ISK meter using SML was tested successfully with 9600 baud/8N1. A 9600 baud/7E1 comparison produced only intermittent data and is not used as the Generic SML default.
- Dynamic discovery found `1-0:1.8.0`, `1-0:2.8.0`, and `1-0:16.7.0`.

Limitation:

- Other meter models, templates marked `limited`, OMS, and arbitrary custom OBIS identifiers have not been verified with representative hardware.
- Template names and configured values do not by themselves prove compatibility with a specific meter firmware or optical head.

Impact:

- Untested templates may require manual serial settings or custom configuration.
- `limited` templates may depend on Legacy pre-command or parser behavior that the standard vzLogger form cannot express.
