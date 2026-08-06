# Local Build Packages

- **Audience:** Developers, testers, maintainers, and AI agents
- **Status:** Current build procedure
- **Authority:** Normative for local package naming and creation

Use local packages for development, installation checks, and focused tests on a disposable LoxBerry. They are not release artifacts and must never be uploaded as an official release.

## Build commands

Build the current worktree:

```powershell
tools/build-local.ps1
```

Add a short reason when the package exists for a particular test:

```powershell
tools/build-local.ps1 -Purpose mapping-test
```

The script reads the version from `plugin.cfg`, snapshots the current worktree
with a temporary Git index, and calls the same canonical package builder and
exact verifier as GitHub Actions. Entries are sorted, stored without
platform-dependent compression, assigned fixed timestamps and Git file modes,
and checked against the exact `git archive --worktree-attributes` export
manifest. `release.cfg`, `prerelease.cfg`, tests, agent instructions, CI files,
developer documentation, and tools are excluded. User documentation and
licenses remain included.

For a clean identical commit, the local ZIP bytes match the official GitHub ZIP;
only the outer local filename and its sidecar filename differ. A dirty package
contains the snapshotted worktree and cannot claim equality with a commit build.

## Naming

Local package names always use this form:

```text
Smartmeter-V<version>-local[-<purpose>]-<short-git-hash>[-dirty].zip
```

Examples:

```text
Smartmeter-V2.0.0.33-local-781af34.zip
Smartmeter-V2.0.0.33-local-mapping-test-781af34.zip
Smartmeter-V2.0.0.33-local-mapping-test-781af34-dirty.zip
```

The purpose is normalized to lowercase ASCII words separated by hyphens. `dirty` means the package contains tracked modifications or non-ignored untracked files that were not part of the named commit. Build only after reviewing `git status --short`, because non-ignored untracked files are included so newly added plugin files can be tested before commit.

## Official releases

The suffixless name is reserved for official GitHub release assets:

```text
Smartmeter-V2.0.0.33.zip
```

Official release ZIPs, tags, and releases are created only by the owner-triggered
GitHub Actions `Publish plugin release` workflow from prepared `master`.
Developers and AI agents must not create, rename, or publish an official-looking
ZIP locally. Follow the [release process](release-process.md) for releases.
