# Tested support matrix

`LB_MINIMUM` and unrestricted architecture metadata are installation gates, not evidence that every permitted system was tested. This matrix records only the latest reproducible `LoxBerry-TEST` result.

| Verified | Repository commit | Plugin | LoxBerry | Operating system | Architecture | vzLogger | Browsers |
|---|---|---|---|---|---|---|---|
| 2026-07-25 | `f2b410ce` | `2.0.0.33` | `4.0.0.13` | Debian 13/trixie | arm64 | `0.8.9` from the configured Cloudsmith repository | Firefox and Chrome; exact versions not recorded |

The target-device test covered update, disable/reactivate, uninstall, fresh installation, service operation, SML/MQTT data flow, calculated power, HTTP cache, and UDP output. The table is updated only after a matching target-device run. Tests of an uncommitted worktree do not replace the recorded commit.

## Additional verification coverage

| Area | Evidence | Boundary |
|---|---|---|
| Configuration, validation, channel UUIDs, Expert Mode, and migration | Automated repository regression tests | Not a substitute for a run with a particular meter |
| D0 and OMS configuration model | Automated generator, form, and validation tests | Not confirmed with representative D0/OMS hardware; OMS additionally depends on the installed vzLogger version |
| Volkszaehler, InfluxDB, and MySmartGrid | Automated generation and validation of supported parameters | No documented end-to-end test against an external target service |
| Recovery, service control, and responsive UI | Automated lifecycle, security, and UI contract tests | Not every path is part of the target-device run recorded above |

“Automated verification” here means that repository tests check generated configuration or expected behavior. It is not a claim that every combination of meter, firmware, reading head, network, and external service has been tested in practice.

Other LoxBerry or operating-system versions and other CPU architectures are not device-tested. Expected compatibility rests on the documented LoxBerry V4, POSIX-shell, dependency, and portability contracts plus code review and is not a tested support claim. Repository availability and root-hook behavior outside the recorded platform remain unconfirmed.
