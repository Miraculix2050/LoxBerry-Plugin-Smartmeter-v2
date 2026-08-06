# Project Instructions

This repository contains the LoxBerry SmartMeter v2 plugin. Keep changes small, compatible with the LoxBerry plugin layout, and focused on the existing shell, Perl, PHP, CGI, template, and configuration files.

The normative product and engineering contracts are consolidated in `docs/development/developer-requirements.md`. Read the relevant sections before changing configuration behavior, mode switching, data models, outputs, permissions, lifecycle handling, or UI behavior.

## Working Rules

- Preserve the LoxBerry plugin structure and metadata contracts in `plugin.cfg`, `release.cfg`, and `prerelease.cfg`.
- Treat `PLUGIN.NAME`, `PLUGIN.FOLDER`, and `AUTHOR` identity fields as stable update identifiers.
- Keep developer-facing comments and documentation in English unless editing German user-facing language files or German documentation.
- For UI text, update the matching language/template files together so German and English views stay consistent.
- Update user documentation and `CHANGELOG.md` whenever behavior, setup, configuration, dependencies, or upgrade steps change.
- Prefer existing scripts and helper patterns over adding new frameworks or dependencies.
- Do not remove or overwrite user configuration defaults in `config/smartmeter.cfg` without a migration path.

## LoxBerry-Specific Checks

- The LoxBerry v4 plugin-management documentation button is driven by `PLUGIN.WEBSITE`, not `AUTHOR.WEBSITE`.
- Upgrade success should include removal of narrowly identified obsolete Legacy installed/runtime artifacts and cron entries, preservation of a compatible active HTTP cache, and restoration of the saved vzLogger desired state through the lifecycle hooks. Legacy-only system dependencies are no longer requested, but an existing shared package is not purged.
- Generic LoxBerry system warnings in install logs are not automatically plugin failures; check the surrounding plugin success markers first.
- Installation and upgrade scripts should be POSIX-shell compatible for the target LoxBerry environment.

## Responsive UI Verification

- Select browser checks from `docs/development/test-strategy.md`, then follow requirements `SM-UI-001` through `SM-UI-012` in `docs/development/developer-requirements.md` and the applicable viewport acceptance checks in `docs/development/test-device-workflow.md`.

## Verification

- After Perl script changes on Windows, run `tools/check-perl-syntax.ps1 <file>` so the checked-in LoxBerry stubs in `.github/ci/perl-lib` are on `@INC`. Use `perl -c` directly only on a LoxBerry system with the real LoxBerry Perl modules available. For PHP files, run `php -l`.
- For install or upgrade behavior, validate against the relevant install log rather than relying only on static review.
- Use `tools/test.ps1 -Profile Changed` during development and rely on `-Profile Full` in pull-request and `master` CI. Tests are change-driven; do not add periodic test runs.
- Deploy to the disposable LoxBerry only when the change crosses a target-specific boundary identified by `docs/development/test-strategy.md`. Deploy only changed runtime files after local checks, then verify the affected syntax, configuration, and service state according to `docs/development/test-device-workflow.md`.
- Do not write to the test target for analysis-only or review-only tasks unless the user explicitly requests it.
- Never store or print test-device passwords or private keys. Use a local SSH configuration or PuTTY saved-session name.
- Resolve the test target through `tools/TestDeviceSettings.ps1`; developers configure it outside the repository with `tools/configure-test-device.ps1`.
- Preserve remote user configuration and runtime data. Back up affected remote files, preserve their modes, and restore the initial configuration and service state after destructive tests.
- After browser-visible changes, test only the affected workflow and the risk-based browser/viewport set selected by `docs/development/test-strategy.md`. Use the acceptance checks in `docs/development/test-device-workflow.md` and avoid repeated screenshots or log reads unless the change or a failure requires them.
- Before committing, check `git status --short` and avoid reverting unrelated local changes.

## Release Work

- Build local test packages only with `tools/build-local.ps1`. Local ZIP names must contain `-local-`, the short Git commit, an optional purpose, and `-dirty` for an uncommitted worktree; see `docs/development/local-builds.md`.
- Never create or publish a suffixless `Smartmeter-V<version>.zip` locally.
  Prepare version, channel metadata, and `CHANGELOG.md` through a reviewed PR.
  Official ZIPs, annotated tags, and releases are created exclusively from
  prepared `master` by the owner-triggered `Publish plugin release` workflow.
  AI agents invoke the same workflow with `gh workflow run` after merge and must
  not merge release preparation without review.
- When asked to create a release, follow `docs/development/release-process.md`.

## GitHub Workflow

- Treat `origin` (`Miraculix2050/LoxBerry-Plugin-Smartmeter-v2`) as the only repository for pushes and pull requests.
- Open pull requests against `origin/master`. Never open pull requests against `mschlenstedt/LoxBerry-Plugin-Smartmeter` or any `upstream` remote.
