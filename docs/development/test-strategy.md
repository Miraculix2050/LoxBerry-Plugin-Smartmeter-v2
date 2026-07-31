# Change-Driven Test Strategy

- **Audience:** Developers, maintainers, reviewers, testers, and AI agents
- **Status:** Current verification strategy
- **Authority:** Normative for selecting automated, test-device, and browser checks

SmartMeter v2 testing is triggered by actual development changes. There are no
daily, weekly, or other periodic test runs. Select the smallest reproducible set
that proves the changed behavior, while keeping the complete deterministic suite
as the pull-request and `master` gate.

## Automated profiles

Use the repository runner for local and CI checks:

```powershell
tools/test.ps1 -Profile Changed
tools/test.ps1 -Profile Full
```

`Changed` selects syntax and regression checks from the effective Git diff. It is
the normal development loop. `Full` runs every deterministic repository check
and is required in pull-request and `master` CI. Use `-Files` for an explicit,
reproducible selection and `-Plan` to inspect the selection without executing it.

The runner reports a test-device or browser recommendation but never accesses
either system automatically. A missing required local runtime makes the result
incomplete rather than reporting a false pass; CI remains the authoritative full
cross-platform execution.

## Change and risk matrix

| Change | Automated checks | Test device | Browser |
| --- | --- | --- | --- |
| Developer documentation, tests, or CI | Selected checks plus full PR CI | No | No |
| Parser, validator, mapping, or other deterministic shared logic | Changed-file syntax and mapped regressions | No, unless LoxBerry wiring changed | No |
| CGI execution, LoxBerry API/path integration, systemd, permissions, or device I/O | Mapped regressions plus full PR CI | Targeted changed workflow | As described below when the browser path is involved |
| UI behavior or AJAX without layout impact | UI/language/security regressions | Only when installed behavior is required | Chrome at `1280x800` and `390x844` |
| Translation-only UI text | Language and UI regressions | Only when installed rendering is required | Both languages at `390x844`; add sizes only for wrapping risk |
| CSS, responsive layout, shared navigation, dialogs, or controls | UI/language/security regressions | Installed page | Full responsive browser matrix |
| Installation, upgrade, uninstall, dependencies, ownership, or lifecycle defaults | Shell, migration, lifecycle, and metadata regressions | Only affected lifecycle scenarios using a local package | Only affected installed UI flows |

Unknown runtime or configuration paths fall back to the full automated profile.
They still do not imply an automatic full device or browser acceptance.

## Browser scope and token efficiency

For executable CGI or navigation changes without a layout change, use one
authenticated Chrome desktop smoke through the normal LoxBerry navigation. For
UI behavior without layout impact, exercise only the changed workflow at the two
primary Chrome sizes. Reserve Chrome plus Firefox at the complete viewport matrix
for shared layout, responsive, navigation, dialog, control, or browser-sensitive
changes.

Reuse the authenticated tab and page state. Batch DOM visibility, horizontal
overflow, relevant keyboard reachability, changed-state, and console-error checks
where possible. Capture screenshots for visual changes or failures, not after
every interaction. Open server logs only when the result or browser console
indicates a failure.

## Test-device and lifecycle scope

Target verification is required when deterministic tests cannot prove a
LoxBerry-specific boundary: executable CGI behavior, native paths or APIs,
systemd state, ownership or modes, lifecycle hooks, hardware, or external output.
Deploy only changed runtime files and exercise only affected services and flows.

Use a package through the normal plugin manager when installation or upgrade
behavior itself changed. Run only the lifecycle scenarios affected by the diff;
a merge or release does not by itself require a complete install/upgrade/uninstall
cycle. Preserve and restore initial configuration and service state as described
in the test-device workflow.
