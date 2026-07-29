# Known issues and compatibility limitations

This document lists confirmed user-visible limitations. It is not an implementation backlog. A limitation remains current until matching evidence narrows or removes it.

## Limited target-platform coverage

The latest confirmed versions and browser families are recorded in the [tested support matrix](support-matrix.en.md). `LB_MINIMUM` only controls installation eligibility; it does not establish tested or promised support.

Other LoxBerry, Debian, or Raspberry Pi OS versions and other CPU architectures have not been tested on a target device. Repository availability and root-hook behavior outside Debian 13/trixie arm64 are not confirmed. Requirements and code review provide portability confidence but do not replace device testing.

## Legacy web security remains frozen

The modern vzLogger administration requires POST with a user-bound CSRF token and escapes persisted values for their HTML context. The functionally frozen Legacy administration does not receive this cross-cutting retrofit and retains its existing CSRF exposure. Keep the complete LoxBerry installation inside a trusted LAN, do not expose its web interface to the Internet, and prefer vzLogger for actively maintained security behavior.

## Meter-template coverage requires representative hardware

Confirmed coverage is one connected ISK meter using SML at 9600 baud/8N1. A comparison at 9600 baud/7E1 produced only intermittent data and is therefore not the Generic SML default. Dynamic discovery found `1-0:1.8.0`, `1-0:2.8.0`, and `1-0:16.7.0`.

Other meter models, templates marked `limited`, OMS, and arbitrary custom OBIS identifiers have not been verified with representative hardware. Template names and configured values do not prove compatibility with a specific meter firmware or reading head. Untested templates may require manual serial values or custom JSONC; `limited` templates may depend on Legacy commands or parsers that the standard vzLogger form cannot express.
