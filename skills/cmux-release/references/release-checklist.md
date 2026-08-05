# Release Checklist

This reference expands the zerocmux release workflow.

## Default path

Prefer the `/release` command. It should handle:

- choosing the version
- gathering commits since the last tag
- updating `CHANGELOG.md`
- running `./scripts/bump-version.sh`
- committing release metadata
- running `./scripts/release-pretag-guard.sh`
- tagging and pushing

## Version policy

Minor bump by default. Patch or major only when explicitly requested or clearly justified by the release scope.

## Changelog

Keep `CHANGELOG.md` user-facing: user-visible fixes, behavior changes, and compatibility notes rank above internal refactors.

## Failure triage

- `release-pretag-guard.sh` fails on a non-monotonic build number: run `./scripts/bump-version.sh`, commit the bump, retry.
- Release automation fails **before** signing: inspect workflow configuration and version metadata.
- Release automation fails **during** signing or notarization: inspect secret availability and Apple account status.

## Asset rename

```bash
./scripts/release-pretag-guard.sh
```

Manual tag flow:

```bash
git tag vX.Y.Z
git push origin vX.Y.Z
gh run watch --repo Enigma-Labs-Technology/zerocmux
```

## Release asset

The expected release asset is:

```text
zerocmux-macos.dmg
```

The README download button points to:

```text
releases/latest/download/zerocmux-macos.dmg
```

If the asset name changes, update every surface that assumes this path.

## Required secrets

Release signing/notarization depends on:

- `APPLE_CERTIFICATE_BASE64`
- `APPLE_CERTIFICATE_PASSWORD`
- `APPLE_SIGNING_IDENTITY`
- `APPLE_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`
- `APPLE_TEAM_ID`

If release automation fails before signing, inspect workflow configuration and version metadata first. If it fails during signing/notarization, inspect the secret availability and Apple account status.
