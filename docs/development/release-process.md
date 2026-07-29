# Release Process

- **Audience:** Maintainers and release operators
- **Status:** Current release procedure
- **Authority:** Normative for official releases

Use this checklist to create an official stable release or prerelease.

## Scope

A release means:

- all intended changes are committed and pushed;
- plugin versions and update metadata are bumped;
- release notes are prepared in `CHANGELOG.md`;
- a Git tag is created and pushed;
- a GitHub Release is created with the release notes;
- the GitHub Release contains the generated plugin ZIP asset.

Official releases are created exclusively through GitHub. Do not build, rename, or upload a suffixless `Smartmeter-V<version>.zip` from a developer workstation. Local packages follow [local-builds.md](local-builds.md) and always contain `-local-` in their filename.

## Release Channels

The two update channels have deliberately independent metadata:

- Every package uses its target version in `plugin.cfg`: `PLUGIN.VERSION`.
- Every package uses the same version in the tag-bound `PLUGIN.WEBSITE` documentation URL: `.../blob/Smartmeter-V<version>/docs/Readme.md`.
- A stable release updates `release.cfg`: `AUTOUPDATE.VERSION`, `ARCHIVEURL`, and `INFOURL`.
- A prerelease updates `prerelease.cfg`: `AUTOUPDATE.VERSION`, `ARCHIVEURL`, and `INFOURL` and leaves `release.cfg` on the latest stable release.
- A stable release may align `prerelease.cfg` to the same version after publication, but this is not required for creating the stable package.

Existing metadata for an older already-published release may retain its historical URL. Every newly published release must use the generated release asset URL, never GitHub's automatic source archive.

On `master`, an implemented but unpublished development version may already be present in `plugin.cfg` and `prerelease.cfg`, including the planned tag and asset URLs. The tag, GitHub Release, and ZIP are not required to exist until publication. Normal branch CI checks only internal development-metadata consistency; the release workflow enforces the matching channel, tag, and generated asset URL at publication time.

Current tag format:

```text
Smartmeter-V<version>
```

Example:

```text
Smartmeter-V2.0.0.10
```

## Checklist

1. Confirm the target version and whether this is a stable release or prerelease.
2. Check `git status --short`; do not include unrelated local changes.
3. Update `plugin.cfg` and only the channel metadata required under **Release Channels**.
   - Update `PLUGIN.WEBSITE` to the exact target tag; never publish a package whose documentation button points to `master`.
   - Use the release asset URL for `ARCHIVEURL`, not the automatic GitHub source archive:

```text
https://github.com/Miraculix2050/LoxBerry-Plugin-Smartmeter-v2/releases/download/Smartmeter-V<version>/Smartmeter-V<version>.zip
```

4. Confirm user documentation is current for changed behavior, setup, configuration, dependencies, and upgrade steps. Check `docs/Readme.md`, `docs/User-Guide.de.md`, and `docs/User-Guide.en.md` when user-facing behavior changed.
5. Move the relevant `CHANGELOG.md` entries from `Unreleased` to the target version and date.
6. Run cheap validation:
   - `tools/check-perl-syntax.ps1 <file>` for changed Perl files on Windows, or `perl -I .github/ci/perl-lib -c <file>` on Linux/macOS;
   - `php -l` for changed PHP files;
   - shell syntax checks where available;
   - inspect changed release metadata with `git diff`.
7. Ensure the required GitHub Actions `Perl and PHP syntax` check passes on the release pull request before merging to `master`.
8. Run the relevant checks from [lifecycle-test-expectations.md](lifecycle-test-expectations.md) on LoxBerry when the release changes installation, upgrade, uninstall, dependencies, services, cron jobs, or default configuration behavior.
9. Commit the release changes.
10. Push the branch.
11. Create an annotated tag on the pushed release commit:

```powershell
git tag -a Smartmeter-V<version> -m "Smartmeter V<version>"
git push origin Smartmeter-V<version>
```

12. Wait for the `Release asset` GitHub Actions workflow to finish. It verifies that the tag version equals `PLUGIN.VERSION`, detects the matching stable or prerelease channel, validates that channel's tag and generated-asset URLs, builds `Smartmeter-V<version>.zip` from the tag with `git archive --worktree-attributes`, creates a draft GitHub Release with the generated ZIP asset, and initially publishes it as a prerelease.
	- The metadata validation also requires `PLUGIN.WEBSITE` to contain the same tag and version.
   - The workflow uploads the ZIP while the release is still a draft because published GitHub Releases can be immutable.
   - If the tag workflow did not run, dispatch `Release asset` manually with the same tag.
13. Verify the GitHub Release title, release notes, and uploaded `Smartmeter-V<version>.zip` asset.
14. For a stable release, promote the verified GitHub Release from prerelease to the latest stable release. Keep prerelease status for a prerelease.
15. Verify the final stable/prerelease flag, GitHub Release page, and the ZIP URL referenced by the corresponding channel configuration.
16. If a release is broken after publishing, create a new patch release instead of rewriting or deleting the published tag.
