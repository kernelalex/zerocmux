# CI runners

Always-on Linux CI runs on RunsOn Flex instances launched in the project's AWS
account. macOS CI runs in ephemeral self-hosted Tart VMs selected by the
`tart-small` label because RunsOn does not support macOS. The experimental
Windows lane remains on GitHub-hosted `windows-latest`.

## RunsOn Flex configuration

Every Linux workflow carries a self-contained Flex request:

- Ubuntu 24.04 x64
- 4 vCPUs
- `c7a`, `c7i`, `m7a`, or `m7i` instance families
- 100 GB gp3 storage
- price-capacity-optimized Spot, with RunsOn's default on-demand interruption
  retry
- default SSH-disabled behavior

No RunsOn extras are enabled. In particular, `otel` must remain disabled to
preserve the project's zero-telemetry policy. The repository continues to use
its explicit GitHub Actions caches; enabling RunsOn cache extras can be
considered separately after the base migration is stable.

Workflows request the shape through a single opaque label:

```yaml
runs-on: runs-on=${{ github.run_id }}-job-name/runner=4cpu-linux-x64/family=c7a+c7i+m7a+m7i/volume=100gb/spot=pco
```

Every job uses a distinct suffix. Matrix jobs also include the matrix value so
GitHub cannot assign one shard to a runner created for another shard.

The shape is inline because this repository is public: RunsOn reads a public
repository's `.github/runs-on.yml` only from the default branch, so a new named
runner would not be available to the migration PR itself. A reusable definition
can replace the inline constraints after it exists on the default branch.

The RunsOn stack is expected to use the default `production` environment. If
multiple RunsOn stacks listen to this repository, add an explicit `region=` or
`env=` constraint to every label so only one stack handles each request.

## macOS lanes

Every macOS workflow routes to `tart-small`. The label belongs only to the
ephemeral Tart pool and is intentionally used without GitHub's default
`self-hosted`, `macOS`, or `ARM64` labels because the pool registers clones
with custom labels only. Each job receives a fresh VM; the compatibility lane
checks ARM64 while Xcode selection enforces the required toolchain and SDK.

The release signing job additionally requests `zerocmux-signing`. Tart release
workers must register both labels or protected tag releases will remain queued.

`perf-activation.yml` and `test-e2e.yml` default their `auto` choice to
`tart-small`; their manual choices no longer expose cloud macOS providers.
`reload-build.yml` also restricts its runner input to `tart-small`.

## Policy checks

`tests/test_ci_self_hosted_guard.sh` rejects legacy provider labels in workflows,
pins every macOS lane to `tart-small`, preserves the release signing capability
label, and rejects OTEL in RunsOn labels. `tests/test_ci_release_sdk_lane.sh`
keeps the release helper and SDK build lanes on the same Tart pool.

Keep Tart capability labels in `.github/actionlint.yaml`. GitHub-hosted labels
and RunsOn's opaque labels do not need entries there.
