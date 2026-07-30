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
- Upgrade success should include removal of obsolete Legacy cron entries and restoration of the saved vzLogger desired state through the lifecycle hooks.
- Generic LoxBerry system warnings in install logs are not automatically plugin failures; check the surrounding plugin success markers first.
- Installation and upgrade scripts should be POSIX-shell compatible for the target LoxBerry environment.

## Responsive UI Verification

- Follow requirements `SM-UI-001` through `SM-UI-012` in `docs/development/developer-requirements.md` and the viewport acceptance matrix in `docs/development/test-device-workflow.md`.

## Verification

- After Perl script changes on Windows, run `tools/check-perl-syntax.ps1 <file>` so the checked-in LoxBerry stubs in `.github/ci/perl-lib` are on `@INC`. Use `perl -c` directly only on a LoxBerry system with the real LoxBerry Perl modules available. For PHP files, run `php -l`.
- For install or upgrade behavior, validate against the relevant install log rather than relying only on static review.
- For implementation tasks that affect installed plugin behavior, deploy only the changed runtime files to the configured disposable LoxBerry test target after local checks, then verify syntax, configuration, and relevant service state on the target. Follow `docs/development/test-device-workflow.md`.
- Do not write to the test target for analysis-only or review-only tasks unless the user explicitly requests it.
- Never store or print test-device passwords or private keys. Use a local SSH configuration or PuTTY saved-session name.
- Resolve the test target through `tools/TestDeviceSettings.ps1`; developers configure it outside the repository with `tools/configure-test-device.ps1`.
- Preserve remote user configuration and runtime data. Back up affected remote files, preserve their modes, and restore the initial configuration and service state after destructive tests.
- After UI, template, CSS, navigation, or user-facing text changes, test the vzLogger page in an authenticated desktop browser and with mobile viewport emulation on the disposable LoxBerry. Use the viewport matrix and checks in `docs/development/test-device-workflow.md`.
- Before committing, check `git status --short` and avoid reverting unrelated local changes.

## Release Work

- Build local test packages only with `tools/build-local.ps1`. Local ZIP names must contain `-local-`, the short Git commit, an optional purpose, and `-dirty` for an uncommitted worktree; see `docs/development/local-builds.md`.
- Never create or publish a suffixless `Smartmeter-V<version>.zip` locally. Official releases and their ZIP assets are created exclusively by the GitHub `Release asset` workflow.
- When asked to create a release, follow `docs/development/release-process.md`.

## GitHub Workflow

- Treat `origin` (`Miraculix2050/LoxBerry-Plugin-Smartmeter-v2`) as the only repository for pushes and pull requests.
- Open pull requests against `origin/master`. Never open pull requests against `mschlenstedt/LoxBerry-Plugin-Smartmeter` or any `upstream` remote.
