# SmartMeter v2 Developer Documentation

- **Audience:** Developers, maintainers, reviewers, testers, and AI agents
- **Status:** Current documentation index

The documents in this directory have distinct authority. Product and engineering
contracts are normative; procedures explain how to verify or publish changes;
tests provide executable evidence but do not silently redefine a contract.

When sources disagree, resolve them in this order: numbered developer requirements and lifecycle contracts define intended behavior; known limitations and the support matrix bound compatibility and security claims; user guides must mirror those contracts; procedures describe execution; tests provide evidence. Do not merge a contradiction by treating current code or a test as an implicit specification change.

Changes to a normative contract require review, a recorded rationale, and matching updates to affected tests, user guides, and `CHANGELOG.md`. No named maintainer role is required by this repository.

## Normative contracts

- [Developer requirements](developer-requirements.md) — current product and engineering behavior
- [Plugin lifecycle test expectations](lifecycle-test-expectations.md) — installation, upgrade, switching, and uninstall acceptance

## Procedures

- [LoxBerry test-device workflow](test-device-workflow.md)
- [Local development packages](local-builds.md)
- [Release process](release-process.md)
- [Compatibility follow-up](compatibility-follow-up.md)

## Architecture reviews

- [Architecture review (2026-07-31)](architecture-review.md) — dated review of
  component boundaries, duplication, testability, and incremental refactoring
  priorities at `master` commit `97b8d9f`

## Related evidence and user contracts

- [German user guide](../User-Guide.de.md)
- [English user guide](../User-Guide.en.md)
- [Known issues and compatibility limitations](../known-limitations.md)
- [Tested support matrix](../support-matrix.md)
- [`CHANGELOG.md`](../../CHANGELOG.md) — historical release notes, not a normative specification
- [Developer changelog](CHANGELOG.md) — implementation detail for the current development cycle
- [`tests/`](../../tests) and [CI workflow](../../.github/workflows/syntax-check.yml) — executable regression evidence

The completed vzLogger migration plan was removed after its accepted behavior was
consolidated into the developer requirements, user guides, lifecycle expectations,
known limitations, and regression tests. Use Git history when historical migration
context is required.
