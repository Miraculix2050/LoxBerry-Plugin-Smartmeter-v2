# Developer Requirements

- **Audience:** Developers, maintainers, reviewers, testers, and AI agents
- **Status:** Current
- **Authority:** Normative product and engineering contract
- **Last structural review:** 2026-07-29

This document records the product and engineering contracts that must remain true when SmartMeter v2 is changed. It consolidates decisions from the vzLogger migration plan, user guides, lifecycle tests, review findings, and project discussions. Detailed procedures remain in the linked specialist documents.

Every normative requirement has a stable `SM-<area>-<number>` identifier. Keep an identifier when wording is clarified without changing its contract. Retire an identifier instead of reusing it for different behavior. The section traceability table links each requirement area to its primary sources and verification evidence; individual tests may cover multiple requirements.

Numbered requirements and lifecycle contracts define intended behavior. `../known-limitations.md` and `../support-matrix.md` bound compatibility and security claims; user guides mirror the resulting user contract; procedures describe execution; tests provide evidence and must not silently redefine a requirement. Resolve contradictions before merging. A normative change requires review, a recorded rationale, and matching updates to affected tests, user guides, and `CHANGELOG.md`.

| Area | Primary source or rationale | Primary verification |
| --- | --- | --- |
| `ARCH`, `COMP` | Accepted product architecture and compatibility behavior | Configuration, runtime, lifecycle, and switching regression tests |
| `SAFE`, `LEG`, `SEC` | Atomicity, security reviews, and LoxBerry ownership boundaries | Web-security, validation, recovery, lifecycle, and runtime tests |
| `MODEL`, `DATA`, `EXPERT` | User-visible configuration and output contracts | Generator, validator, channel, custom-channel, bridge, HTTP, and expert tests |
| `LIFE` | LoxBerry V4 lifecycle contract and confirmed target behavior | Lifecycle expectations, lifecycle regression tests, and target-device evidence |
| `UI` | German/English user guides and responsive product decisions | Language, UI, live-chart, authenticated desktop, and mobile checks |
| `VER` | Repository quality and release policy | CI plus the linked test-device, local-build, and release procedures |

## Using Project History

- This file and the documentation on `master` describe behavior implemented in the current development tree, not a released version, speculative future behavior, or every behavior that existed during the migration.
- Treat `CHANGELOG.md`, older commits, target evidence, and completed historical plans as context. Do not turn an old MVP limitation, temporary workaround, retired file path, or version-specific observation into a current requirement.
- Before adding or changing a requirement, compare the latest accepted behavior in the current user guides, executable tests, `../known-limitations.md`, recent commits, and the `Unreleased` changelog. Resolve contradictions explicitly and update or remove superseded documentation.
- Historical evidence may justify a current rule, but the rule must be stated independently of the old version, date, test device, or implementation accident.

## 1. Product Architecture

- **SM-ARCH-001** — vzLogger is the only meter-reading implementation and is installed as an external apt package; it must not be bundled with the plugin.
- **SM-ARCH-002** — vzLogger reads meters and publishes MQTT. The SmartMeter bridge consumes MQTT and provides the plugin HTTP cache and optional UDP output. The bridge must not read serial devices directly.
- **SM-ARCH-003** — `VZLOGGER.ENABLED` is the persistent desired state. Manual Start, Stop, and Restart are temporary runtime actions and must not change it.
- **SM-ARCH-004** — The UI exposes one configuration page. Activation changes take effect only after an explicit Save/Apply action.
- **SM-ARCH-005** — The existing LoxBerry plugin identity fields (`AUTHOR`, `PLUGIN.NAME`, and `PLUGIN.FOLDER`) are stable update identifiers and must not change.

## 2. Compatibility And Mode Switching

- **SM-COMP-001** — Existing `smartmeter.cfg`, MQTT topic structure, HTTP-cache keys, UDP value names, custom JSONC files, and generated-config locations are compatibility contracts. Change them only with an explicit migration and documented upgrade path.
- **SM-COMP-002** — A valid generated `vzlogger.conf` must survive a disabled desired state, upgrades, and later vzLogger reactivation. Reactivation validates and reuses it.
- **SM-COMP-003** — Existing 2.0.1 vzLogger channel definitions, stable UUIDs, and configured output keys remain compatible. Obsolete `legacy_keys` and `legacy_names` fields are removed during configuration cleanup and are not runtime aliases.
- **SM-COMP-004** — Ordinary read-only page loads must not rewrite configuration files, cron entries, or services.
- **SM-COMP-005** — Meter or channel removal is staged in the browser and becomes persistent only on Save/Apply. Applying a meter removal also removes only that meter's owned sidecars, mappings, discovery/test artifacts, logs, and runtime cache.

## 3. Save, Apply, And Service Safety

- **SM-SAFE-001** — Every top-level action that changes persistent configuration, desired service state, drafts, mappings, generated runtime artifacts, recovery settings, discovery state, systemd units, autostart, or final service state uses the same non-blocking exclusive lock at `/var/run/shm/<actual-plugin-folder>/vzlogger_config.lock`. Mutating CGI, CLI, service control, recovery control, and lifecycle entry points are included. A nested synchronous helper reuses only a verified inherited descriptor for that lock; an independent background child closes the descriptor and clears its inherited lock metadata before continuing. Status, non-mutating validation and diagnostics, MQTT/HTTP/UDP output, cache writes, log writes, and internal helpers coordinated by an already locked parent do not acquire it. A busy top-level action is rejected with an actionable message and no state change.
- **SM-SAFE-002** — Every mutating CGI action requires POST and a valid HMAC-based CSRF token bound to the authenticated LoxBerry user. The runtime-only CSRF secret rotates when the RAM-backed runtime directory is cleared.
- **SM-SAFE-003** — Generated runtime artifacts are created in a protected staging directory on the same filesystem, validated as one coherent set, and then promoted atomically with backups. Any promotion failure must roll back the complete set and preserve the last valid runtime configuration.
- **SM-SAFE-004** — Submitted user settings may remain saved after a failed Apply so they can be corrected; invalid generated runtime files must never replace the active valid set.
- **SM-SAFE-005** — Validate Config is non-mutating: it uses a temporary draft and must not change saved settings, generated files, custom meter sources, cron, or services.
- **SM-SAFE-006** — Apply succeeds only when generation, validation, promotion, service override handling, and every requested final service state succeed. Failures propagate to CGI/CLI callers as non-zero results.
- **SM-SAFE-007** — Start and Restart validate the existing generated configuration and change only the requested service activation and its dedicated log settings. They must not save unrelated form fields. Stop remains available for a running service even when configuration is invalid.
- **SM-SAFE-008** — The optional Loxone recovery endpoint is POST-only and token-authenticated. It may restart an active expected unit or recover an enabled failed unit, but it must never start an inactive, administratively disabled, unconfigured, or optional-disabled unit. Recovery must not install or enable units.
- **SM-SAFE-009** — Service controls and lifecycle hooks must report the observed final service state, not only a successful command invocation.

## 4. Removed Legacy Contract

- **SM-LEG-001** — SmartMeter v2 2.1.0.0 contains no executable Legacy reader, parser, poller, cron helper, CGI, template, localization namespace, mode switch, or data-transfer path. The immutable `Smartmeter-V2.0.1.0` tag retains the final Legacy implementation; the protected `legacy-2.0` branch carries the supported 2.0.1.x maintenance line, currently 2.0.1.1.
- **SM-LEG-004** — Upgrade must abort before file replacement when `MAIN.IMPLEMENTATION=legacy`, or when an older configuration has no implementation value and `MAIN.READ=1`. The message directs users to use the latest supported 2.0.1.x Legacy maintenance release, activate vzLogger, and successfully Save/Apply before upgrading again.
- **SM-LEG-005** — Allowed upgrades atomically migrate `vzlogger` to `VZLOGGER.ENABLED=1`, `none` to `VZLOGGER.ENABLED=0`, and `MAIN.READ` to `VZLOGGER.BRIDGEENABLED`, then remove all mode, cron, Legacy MQTT, and `LEGACY_*` values plus narrowly identified installed Legacy artifacts.

## 5. Meter And Channel Model

- **SM-MODEL-001** — vzLogger uses one neutral meter-template catalog. Maintain meter models and serial defaults once. The historically grown entries record project best practices and experience, not complete representative-hardware support. SML uses the operating/read baud rate; D0 retains separate initial and read baud rates.
- **SM-MODEL-002** — The standard editor supports SML, D0, and OMS. Protocol-specific fields must not leak into generated objects for another protocol. Unsupported behavior must be reported rather than silently approximated.
- **SM-MODEL-003** — vzLogger runs only when `VZLOGGER.ENABLED=1`, at least one meter is active, and the generated configuration is valid. A meter without channels may remain valid for discovery with a warning. An enabled configuration without meters is an accepted stopped state and removes the plugin override.
- **SM-MODEL-004** — OBIS discovery uses the reader's current browser settings, runs independently of the page request, survives navigation/reload, supports cancellation, and restores the regular vzLogger service afterwards. Discovered identifiers remain available for user selection; a restoration warning must not discard successful discovery results.
- **SM-MODEL-005** — Custom JSONC represents exactly one complete vzLogger meter object, is limited to 64 KiB, and is preserved textually including comments and formatting. Generation may supply missing channel UUID/API values internally but must not rewrite the source JSONC.
- **SM-MODEL-006** — `vzlogger_channel_definitions.json` is the authoritative UI model for active and inactive channel definitions. `vzlogger_channels.json` contains only active plugin outputs used by the bridge.
- **SM-MODEL-007** — Custom-channel identity is maintained by the versioned `vzlogger_user_channel_uuids_<serial>.json` registry. Explicit UUIDs always win. Otherwise a canonical SHA-256 channel fingerprint maps to an ordered UUID list so identical duplicates and channel reordering remain stable. Content changes may create a new UUID; only an explicit UUID guarantees identity across such changes.
- **SM-MODEL-008** — Manual duplicate OBIS channels are valid when they have distinct UUIDs. Discovered channels are normally deactivated instead of deleted so later discovery can find them again.
- **SM-MODEL-009** — SML/D0 storage index `*F` accepts `0..254`. Empty, `null`, and `255` mean unspecified and are not emitted as a redundant `*255`; OMS does not support this field.
- **SM-MODEL-010** — Channel aggregation and meter `aggfixedinterval` are temporal settings available only when the meter has `aggtime > 0`. A disabled aggregation retains the saved fixed-interval choice but does not generate it. Retained settings for an inactive API are neither validated nor generated.
- **SM-MODEL-011** — Output keys are unique per reader, case-insensitively, and are the only HTTP-cache/UDP names emitted for that channel. Existing keys must not be renamed automatically or supplemented with compatibility aliases. Keys are 1–64 characters and accept letters, digits, spaces, and `_ # | ( ) [ ] / ' % $ ! . * -`; `:` and `;` remain reserved delimiters.

## 6. MQTT, Cache, HTTP, And UDP

- **SM-DATA-001** — vzLogger publishes below `<base-topic>/vzlogger`. From the applied `vzlogger.conf` and `vzlogger_channels.json`, the bridge derives exactly one subscription for each active managed output: `chnN/agg` only when meter `aggtime > 0` and channel `aggmode != none`, otherwise `chnN/raw`. It must not subscribe to `#`, `/id`, `/uuid`, both raw and aggregate values, or channels not enabled for SmartMeter output. Arbitrary Expert-mode base topics remain supported.
- **SM-DATA-002** — The bridge MQTT output is the first output option. It inherits the applied vzLogger broker, port, authentication, TLS, QoS, and retain settings and publishes one aggregate JSON payload on the sibling topic `<base-topic>/bridge`. Each meter serial contains `Last_UpdateUnix` in whole UTC seconds and `Last_UpdateLoxEpoche`, calculated by subtracting the fixed epoch offset `1230768000` and adding the LoxBerry local UTC offset valid at the measurement time for Loxone `<v.u>` display. MQTT publication follows timestamps from the selected effective `/agg` or `/raw` channel payload, is deduplicated by whole second per meter, and does not wait for the cache/UDP update cycle or use a separate heartbeat.
- **SM-DATA-003** — Bridge mapping resolves UUID/`chnN` first. Identifier fallback is allowed only when it is unambiguous. Scaling and calculated-power recognition use structured OBIS identifiers, not display or output names.
- **SM-DATA-004** — Cache and UDP output start with `Last_Update` and `Last_UpdateLoxEpoche`, followed by configured outputs in ascending `chnN` order and then unmapped values alphabetically. HTTP and UDP expose the same ordered value set.
- **SM-DATA-005** — `Last_UpdateUnix` remains UTC and monotonic. `Last_UpdateLoxEpoche` in MQTT, cache, and UDP uses the LoxBerry timezone and daylight-saving rule at the selected measurement or receive timestamp and can move backwards at the autumn transition. Meter `use_local_time` selects the timestamp source inside vzLogger but does not change this downstream formatting. Bridge MQTT timestamp output is effective only while the applied source has `mqtt.timestamp=true`; disabling source timestamps persists the bridge option as off and must not prevent scalar `/raw` or `/agg` values from feeding HTTP cache and UDP. Re-enabling source timestamps does not restore the output automatically.
- **SM-DATA-006** — Electrical SML energy counters are displayed in kWh when vzLogger supplies Wh. Calculated consumption/delivery power continues to use counter deltas when the meter provides no instantaneous power channel.
- **SM-DATA-007** — HTTP cache output is optional. When disabled, the bridge removes existing `.data` files and performs no further cache writes; the HTTP endpoint reports that the cache is disabled. The runtime cache path remains RAM-backed below `/var/run/shm`.
- **SM-DATA-008** — The bridge update cycle controls only enabled HTTP-cache writes and UDP sends. MQTT timestamp publication is independent of this cycle.
- **SM-DATA-009** — When HTTP cache is enabled, the web UI shows cache availability, last update, and a link to the cache endpoint. It does not need to duplicate the complete cached value list inline.
- **SM-DATA-010** — MQTT passwords, private-key passwords, tokens, and similar secrets must never appear in rendered HTML, unmasked diagnostics, process listings, or logs.
- **SM-DATA-011** — Recovery tokens are generated with at least 256 bits of entropy, stored only as a hash, and accepted only in the dedicated HTTP header. An optional exact source-IP allow-list may add defense in depth without trusting proxy headers.
- **SM-DATA-012** — LoxBerry and this plugin are supported only inside a trusted LAN. The unauthenticated vzLogger HTTP service, public HTTP cache, and recovery endpoint must not be exposed through router port forwarding or a public reverse proxy; their UI and documentation warn about live-reading privacy and plain-HTTP token confidentiality.
- **SM-DATA-013** — The recovery UI mirrors Loxone's hierarchy: one virtual output shows the unauthenticated base addresses using LoxBerry's configured HTTP/HTTPS ports, while separate virtual output commands show the ON command path, token header, empty body, and POST method. LoxBerry credentials must not be embedded because the recovery token is the endpoint authentication.
- **SM-DATA-014** — The bridge remains optional and disabled on a fresh installation. Its new-install output defaults are MQTT enabled, HTTP cache disabled, and UDP disabled; they take effect only after the bridge itself is enabled. Upgrades preserve the former behavior by leaving bridge MQTT disabled and HTTP cache enabled until the user changes them.

## 7. Expert Mode

- **SM-EXPERT-001** — Expert Mode edits a separate persistent `vzlogger_expert.conf` draft. Enabling or disabling the mode must not silently overwrite either the draft or active `vzlogger.conf`.
- **SM-EXPERT-002** — While Expert Mode is active, standard vzLogger configuration fields are read-only. Bridge controls and service logging remain independently editable.
- **SM-EXPERT-003** — Invalid expert input remains available for correction while the last valid runtime configuration stays active. Unknown upstream extension fields produce warnings and are preserved.
- **SM-EXPERT-004** — Reinitializing the expert draft from the current `vzlogger.conf` is explicit, confirmed, and visible only while Expert Mode is active.
- **SM-EXPERT-005** — Expert mappings are retained by known UUID. Unknown UUIDs are reported and are not automatically published by the bridge.

## 8. Security And File Ownership

- **SM-SEC-001** — Do not create additional Linux users or groups. Use the existing `loxberry` user, `_vzlogger` user, and `loxberry` group.
- **SM-SEC-002** — Runtime directories use `loxberry:loxberry 0750`; runtime files use at most `0640`.
- **SM-SEC-003** — Mapping, definitions, UUID sidecars, and custom JSON/JSONC use `loxberry:loxberry 0600`.
- **SM-SEC-004** — `vzlogger.conf` uses `loxberry:<primary _vzlogger group> 0640`; the vzLogger log uses `_vzlogger:loxberry 0640`.
- **SM-SEC-005** — Serial devices use `root:loxberry 0660`. The vzLogger override uses `SupplementaryGroups=loxberry`; plugin systemd units use a restrictive `UMask` (`0027`).
- **SM-SEC-006** — Never reintroduce `0777`/`0666` fallbacks. Install and upgrade hooks repair required ownership and modes idempotently.

## 9. Lifecycle And Ownership Boundaries

- **SM-LIFE-001** — Fresh installation sets `VZLOGGER.ENABLED=1` and `VZLOGGER.BRIDGEENABLED=0`. With no configured meter, both services remain stopped. Allowed upgrades preserve the corresponding previous vzLogger or inactive desired state.
- **SM-LIFE-002** — Apply starts configured services only when their desired states and dependencies are satisfied. Disabled or meterless Apply stops services and removes the vzLogger override without deleting the last valid generated configuration. Upgrade and uninstall remove obsolete Legacy cron references.
- **SM-LIFE-003** — The plugin-managed systemd drop-in points vzLogger to the plugin-owned configuration. Never overwrite an unrelated `/etc/vzlogger.conf`.
- **SM-LIFE-004** — Uninstall removes plugin-owned services, drop-ins, runtime/cache artifacts, udev rules, apt source/key, and only packages proven by an ownership marker to have been introduced by the plugin.
- **SM-LIFE-005** — Broader platform or meter support must not be claimed without matching target-system or representative-hardware evidence. `LB_MINIMUM` and architecture metadata are installation gates, not test evidence. The latest confirmed platform remains in `../support-matrix.md`; current limitations remain in `../known-limitations.md`. Coding rules and review may support an expectation of portability but must not be described as device-tested support.
- **SM-LIFE-006** — Bridge, Control, Web UI, and on-demand diagnostics use registered LoxBerry log sessions. Continuous/action logging follows the single SmartMeter v2 plugin log level and must not create an empty session when all messages are filtered. Identical operational Bridge errors and warnings from recurring measurement work emit immediately and then no more than once per 60 seconds with a suppressed-repeat count; bounded throttle state must not alter or sample Debug output. Native vzLogger logging remains independently configurable and writes only to `vzlogger-native.log` when enabled; no plugin-specific rotation competes with LoxBerry log maintenance. Transient OBIS discovery logs remain RAM-backed and are removed after consumption.

## 10. UI, Localization, And Accessibility

- **SM-UI-001** — Desktop and mobile browsers provide the same functions and information. Follow the responsive viewport and acceptance requirements in `../../AGENTS.md` and `test-device-workflow.md`.
- **SM-UI-002** — German and English UI phrases, templates, validation messages, and user documentation must remain synchronized. Exercise the longer German labels during responsive testing.
- **SM-UI-003** — Current plugin UI translations live only in LoxBerry's native `templates/lang/language_de.ini` and `language_en.ini` resources, separated into shared and vzLogger namespaces. Do not restore duplicate `language.txt` trees or custom language loaders.
- **SM-UI-004** — Localize only plugin-authored text written for users in the browser, including the explanatory part of browser validation and action messages. Do not localize established technical terms, product or project names, protocol and format identifiers, commands, paths, configuration keys, API values, systemd states, or comparable machine-relevant identifiers.
- **SM-UI-005** — Keep technical CLI output, logs, and unmodified diagnostics from the operating system, systemd, or external programs in English. This keeps operation, troubleshooting, and automated evaluation language-independent; a localized UI may add a translated explanation without rewriting the technical detail.
- **SM-UI-006** — Disabled controls preserve their values and visually disable the associated label/help region. Unsaved state must be visible where activation, meter, template, or channel state has changed.
- **SM-UI-007** — AJAX workflows must preserve page context and expanded panels, show progress, distinguish success/warning/failure, and avoid saving unrelated settings.
- **SM-UI-008** — Recurring service, OBIS-discovery, and live-data polling uses authenticated lightweight endpoints. The live-data proxy may reuse only successful, validated JSON responses from an atomic RAM-backed cache for at most one second; error responses are never cached. Service state is refreshed every ten seconds while visible. Live readings default to a two-second cadence; the browser-local chart settings may select 2 seconds, 10 seconds, 30 seconds, 1 minute, 2 minutes, or 5 minutes for requests, table, history, and chart updates. Failures back off temporarily without shortening the selected interval.
- **SM-UI-009** — Closed meter panels and channel-detail controls are initialized on demand. The hidden channel document remains authoritative so deferred controls do not change saved values.
- **SM-UI-010** — The rendered live-data history is browser-local and persistent without LoxBerry disk writes. It uses bounded multi-resolution retention (raw values for 15 minutes, 10-second extrema through 2 hours, one-minute extrema through 24 hours, and 15-minute extrema through 7 days), preserves gaps, counter resets, and peaks, and discards only channel histories whose data semantics changed.
- **SM-UI-011** — For readable long-range charts, render instantaneous values as temporal averages (30 seconds through 2 hours, 5 minutes through 24 hours, and 30 minutes through 7 days) and energy counters as the last value in each display interval. Persist exact sums and sample counts alongside first/last/minimum/maximum so averages remain unbiased, while summaries continue to use retained extrema and counter edges.
- **SM-UI-012** — Never expose an unmasked generated configuration or expert editor outside the authenticated frontend.

## 11. Verification And Documentation

- **SM-VER-001** — Regression tests belong under `tests/`, must be deterministic and reusable, and should test shared modules without requiring a live MQTT broker or production filesystem where possible.
- **SM-VER-002** — Testing is triggered by actual development changes, never by a periodic schedule. Run changed-file checks during development and the complete deterministic suite for pull requests and `master`. Deploy to the disposable LoxBerry only when the diff crosses a target-specific boundary that deterministic tests cannot prove, as selected by `test-strategy.md` and executed through `test-device-workflow.md`.
- **SM-VER-003** — Browser verification is risk-based. Executable CGI/navigation changes require an authenticated Chrome desktop smoke through the normal LoxBerry path. UI behavior without layout impact requires the changed workflow in Chrome at `1280x800` and `390x844`. Translation-only changes require both languages at the primary mobile size, with additional sizes only for wrapping risk. Shared layout, responsive, navigation, dialog, control, or browser-sensitive changes require Chrome at `1280x800`, `900x768`, and `390x844`, plus smoke checks at `360x800` and `320x568`. Verify the effective CSS viewport before acceptance, then limit keyboard, overflow, clipping, interaction, console, screenshot, and log checks to affected behavior. Lifecycle changes require only the affected evidence from `lifecycle-test-expectations.md`.
- **SM-VER-004** — Preserve remote configuration and service state during tests. Verify checksums around failed, concurrent, or read-only actions.
- **SM-VER-005** — Update both user guides and `CHANGELOG.md` when behavior, configuration, dependencies, compatibility, or upgrade steps change. Record confirmed limitations in `../known-limitations.md` rather than presenting them as supported.
- **SM-VER-006** — Local packages and official releases follow `local-builds.md` and `release-process.md`; suffixless release archives are produced only by the GitHub release workflow.
- **SM-VER-007** — `PLUGIN.WEBSITE` and in-product manual links in an installed package target `docs/Readme.md` or the selected language guide at the matching `Smartmeter-V<PLUGIN.VERSION>` tag. Only development documentation links may target `master`.

## Detailed References

- User-visible behavior: `../User-Guide.de.md` and `../User-Guide.en.md`
- Installed-device and browser verification: `test-device-workflow.md`
- Test selection and risk model: `test-strategy.md`
- Lifecycle acceptance: `lifecycle-test-expectations.md`
- Compatibility evidence: `../support-matrix.md`; limitations: `../known-limitations.md`
- Release procedure: `release-process.md`
- Historical migration context: Git history; the completed implementation plan has been removed
