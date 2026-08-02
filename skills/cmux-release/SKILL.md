---
name: zerocmux-release
description: "zerocmux release workflow, version bumping, changelog updates, pretag guard, release tags, and release asset expectations. Use when preparing or troubleshooting a zerocmux release."
---

# zerocmux Release

Prefer the `/release` command. It determines the new version (minor by default), gathers commits since the last tag, updates `CHANGELOG.md`, runs `./scripts/bump-version.sh`, commits, runs `./scripts/release-pretag-guard.sh`, then tags and pushes.

The docs changelog page at `web/app/[locale]/(landing)/docs/changelog/page.tsx` renders from `CHANGELOG.md`, so there is no separate docs changelog source to update.

## Version bumping

```bash
./scripts/bump-version.sh          # minor (0.15.0 -> 0.16.0)
./scripts/bump-version.sh patch    # 0.15.0 -> 0.15.1
./scripts/bump-version.sh major    # 0.15.0 -> 1.0.0
./scripts/bump-version.sh 1.0.0    # explicit version
```

This updates `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`. The build number auto-increments and must increase for Sparkle auto-update to work. Bump the minor version unless explicitly asked otherwise.

## Tagging

```bash
./scripts/release-pretag-guard.sh
git tag vX.Y.Z
git push origin vX.Y.Z
gh run watch --repo kernelalex/zerocmux
```

If the pretag guard fails, run `./scripts/bump-version.sh`, commit the build-number bump, then retry.

- Requires GitHub secrets: `APPLE_CERTIFICATE_BASE64`, `APPLE_CERTIFICATE_PASSWORD`, `APPLE_SIGNING_IDENTITY`, `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, `APPLE_TEAM_ID`.
- The release asset is `zerocmux-macos.dmg` attached to the tag.
- README download button points to `releases/latest/download/zerocmux-macos.dmg`.
- Bump the minor version for updates unless explicitly asked otherwise.
- Update `CHANGELOG.md`; docs changelog is rendered from it.

## Detailed reference

- [references/release-checklist.md](references/release-checklist.md): changelog tone, failure triage, and asset-rename fallout.
