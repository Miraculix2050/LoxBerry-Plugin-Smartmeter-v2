# Compatibility Follow-up

- **Audience:** Maintainers, developers, and testers
- **Status:** Current evidence backlog
- **Authority:** Non-normative work list; `docs/known-limitations.md` remains authoritative for current claims

This document tracks the work needed to narrow confirmed compatibility limitations.
Completing an item does not expand support by itself: record the evidence, update
`docs/known-limitations.md`, and adjust the user guides before making a broader claim.

## Platform coverage

- Define an explicit supported-platform matrix before claiming broader compatibility.
- Add one real installation test per supported OS/codename and architecture combination.
- Record the tested LoxBerry, operating-system, architecture, vzLogger, and plugin versions with the lifecycle and runtime results.

## Meter-template coverage

- Test additional templates only when matching physical meters are available.
- Prioritize templates marked `limited` and OMS when expanding documented hardware support.
- Record the meter model and firmware, optical head, serial settings, discovered identifiers, and sustained runtime behavior.
