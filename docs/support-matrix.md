# Tested Support Matrix

- **Audience:** SmartMeter v2 users, administrators, maintainers, and reviewers
- **Status:** Latest recorded target-device evidence
- **Authority:** Normative for claims that a platform was tested

`LB_MINIMUM` and unrestricted architecture metadata are installation gates, not evidence that every permitted system was tested. This matrix records only the latest reproducible `LoxBerry-TEST` result; it does not contain raw logs or detailed test reports.

| Verified | Repository commit | Plugin | LoxBerry | Operating system | Architecture | vzLogger | Browsers |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-07-25 | `f2b410ce` | `2.0.0.32` | `4.0.0.13` | Debian 13/trixie | arm64 | `0.8.9` from the configured Cloudsmith repository | Firefox and Chrome; exact versions were not recorded |

This target covered upgrade, disable/reactivate, uninstall, fresh install, service operation, SML/MQTT data flow, calculated power, HTTP cache, and UDP delivery. The table is updated only after a matching target-device run. Uncommitted worktree tests do not replace the recorded commit.

Other LoxBerry or operating-system versions and other CPU architectures are not device-tested. Expected compatibility there rests on the documented LoxBerry V4, POSIX-shell, dependency, and portability contracts plus code review; it is not a tested support claim. Repository availability and root-hook behavior outside the recorded platform remain unconfirmed.
