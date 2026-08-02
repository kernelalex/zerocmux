#!/usr/bin/env bash
# Pins the expensive macOS jobs and the release signing lanes to the sanctioned
# Blacksmith macOS runners. This keeps those lanes from silently drifting back
# to GitHub-hosted macos-* runners or onto other third-party/self-hosted
# providers (warp-/depot-) that the project does not run always-on CI on.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORKFLOW_DIR="$ROOT_DIR/.github/workflows"
CI_FILE="$WORKFLOW_DIR/ci.yml"
GHOSTTYKIT_FILE="$WORKFLOW_DIR/build-ghosttykit.yml"
COMPAT_FILE="$WORKFLOW_DIR/ci-macos-compat.yml"
RELEASE_FILE="$WORKFLOW_DIR/release.yml"

check_runner() {
  local file="$1" job="$2" pattern="$3" description="$4"
  local job_body
  job_body="$(awk -v job="$job" '
    $0 ~ "^  "job":" { in_job=1; next }
    in_job && /^  [^[:space:]]/ { in_job=0 }
    in_job { print }
  ' "$file")"
  if ! grep -Eq "$pattern" <<<"$job_body"; then
    echo "FAIL: $job in $(basename "$file") must use $description"
    exit 1
  fi
  echo "PASS: $job uses $description"
}

if grep -R -n -E 'runs-on:.*(warp-macos|depot-)|os: (warp-macos|depot-)' "$WORKFLOW_DIR"; then
  echo "FAIL: always-on workflows must not hardcode warp-/depot- runner labels (use Blacksmith or GitHub-hosted runners)"
  exit 1
fi
printf '%s\n' "$*" >> "$CMUX_STUB_CURL_LOG"
printf 'fake certificate\n' > "$output"
EOF
  chmod +x "$bin_dir/curl"

  cat > "$bin_dir/security" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  add-certificates)
    printf '%s\n' "$*" >> "$CMUX_STUB_SECURITY_LOG"
    ;;
  find-certificate)
    added_count="$(grep -c '^add-certificates ' "$CMUX_STUB_SECURITY_LOG" 2>/dev/null || true)"
    if [[ "${CMUX_STUB_CERT_COUNT_OVERRIDE:-}" != "" ]]; then
      added_count="$CMUX_STUB_CERT_COUNT_OVERRIDE"
    fi
    for ((i = 0; i < added_count; i++)); do
      printf '%s\n' '-----END CERTIFICATE-----'
    done
    ;;
  *)
    echo "unexpected security command: $*" >&2
    exit 1
    ;;
esac
EOF
  chmod +x "$bin_dir/security"

  # --- Vendored path (default): the real helper has the certs committed beside
  # it, so it must import both WITHOUT touching the network. ---
  if ! PATH="$bin_dir:/usr/bin:/bin" CMUX_STUB_CURL_LOG="$curl_log" CMUX_STUB_SECURITY_LOG="$security_log" "$helper" "$keychain" >"$tmp_dir/success.out" 2>"$tmp_dir/success.err"; then
    echo "FAIL: signing helper behavior test should import both intermediates from vendored copies"
    cat "$tmp_dir/success.err" >&2 || true
    exit 1
  fi

  if [[ -s "$curl_log" ]]; then
    echo "FAIL: signing helper must not hit the network when vendored intermediates are present"
    cat "$curl_log" >&2 || true
    exit 1
  fi

  if [[ "$(grep -c -- '-k '"$keychain" "$security_log")" -ne 2 ]]; then
    echo "FAIL: signing helper behavior test did not add both vendored certificates to the requested keychain"
    exit 1
  fi

  # --- Fallback path: run a copy of the helper with no vendored certs beside it
  # (VENDOR_DIR resolves next to the script). It must download both intermediates. ---
  local fb_dir fb_helper fb_curl_log fb_security_log fb_keychain
  fb_dir="$tmp_dir/fallback"
  mkdir -p "$fb_dir"
  fb_helper="$fb_dir/import-apple-developer-id-intermediates.sh"
  cp "$helper" "$fb_helper"
  chmod +x "$fb_helper"
  fb_curl_log="$tmp_dir/fb_curl.log"
  fb_security_log="$tmp_dir/fb_security.log"
  fb_keychain="$tmp_dir/fb_build.keychain"
  touch "$fb_curl_log" "$fb_security_log" "$fb_keychain"

  if ! PATH="$bin_dir:/usr/bin:/bin" CMUX_STUB_CURL_LOG="$fb_curl_log" CMUX_STUB_SECURITY_LOG="$fb_security_log" "$fb_helper" "$fb_keychain" >"$tmp_dir/fb.out" 2>"$tmp_dir/fb.err"; then
    echo "FAIL: signing helper fallback should download and import both intermediates"
    cat "$tmp_dir/fb.err" >&2 || true
    exit 1
  fi

  for cert in DeveloperIDCA.cer DeveloperIDG2CA.cer; do
    if ! grep -Fq "https://www.apple.com/certificateauthority/$cert" "$fb_curl_log"; then
      echo "FAIL: signing helper fallback did not download $cert when no vendored copy was present"
      exit 1
    fi
  done

  if [[ "$(grep -c -- '-k '"$fb_keychain" "$fb_security_log")" -ne 2 ]]; then
    echo "FAIL: signing helper fallback did not add both downloaded certificates to the requested keychain"
    exit 1
  fi

  # --- Count guard: helper must fail when fewer than two intermediates land. ---
  if PATH="$bin_dir:/usr/bin:/bin" CMUX_STUB_CURL_LOG="$curl_log" CMUX_STUB_SECURITY_LOG="$security_log" CMUX_STUB_CERT_COUNT_OVERRIDE=1 "$helper" "$keychain" >"$tmp_dir/fail.out" 2>"$tmp_dir/fail.err"; then
    echo "FAIL: signing helper behavior test should fail when fewer than two intermediates are visible"
    exit 1
  fi

  if ! grep -Fq "Expected both Developer ID intermediate certificates" "$tmp_dir/fail.err"; then
    echo "FAIL: signing helper behavior test missing count failure diagnostic"
    exit 1
  fi

  rm -rf "$tmp_dir"
  echo "PASS: signing helper imports vendored intermediates offline, downloads as fallback, and verifies the count"
}

check_sentry_cli_install_portability() {
  local helper="$ROOT_DIR/scripts/ensure-sentry-cli.sh"
  if [[ ! -x "$helper" ]]; then
    echo "FAIL: sentry-cli helper must exist and be executable"
    exit 1
  fi

  for needle in \
    'INSTALL_DIR="${RUNNER_TEMP:-/tmp}/sentry-cli-bin"' \
    'SENTRY_CLI_ASSET="sentry-cli-Darwin-universal"' \
    'SENTRY_CLI_SHA256="dcede3b42632886a32753ad9d763f785d46afd5fa4580b5c979aad2d465d1cf5"' \
    'https://github.com/getsentry/sentry-cli/releases/download/${SENTRY_CLI_VERSION}/${SENTRY_CLI_ASSET}' \
    'SENTRY_CLI_VERSION="3.3.0"' \
    '--connect-timeout 20' \
    '--max-time 120' \
    'ACTUAL_SHA256="$(shasum -a 256 "$DOWNLOAD_PATH" | awk' \
    'install -m 0755 "$DOWNLOAD_PATH" "$INSTALL_DIR/sentry-cli"'; do
    if ! grep -Fq -- "$needle" "$helper"; then
      echo "FAIL: sentry-cli helper must contain $needle"
      exit 1
    fi
  done
  if grep -Fq 'command -v sentry-cli' "$helper"; then
    echo "FAIL: sentry-cli helper must not reuse ambient runner PATH state"
    exit 1
  fi

  for file in "$ROOT_DIR/.github/workflows/nightly.yml" "$ROOT_DIR/.github/workflows/release.yml"; do
    if grep -Fq 'brew install getsentry/tools/sentry-cli' "$file"; then
      echo "FAIL: $(basename "$file") must not require Homebrew for sentry-cli on self-hosted signing runners"
      exit 1
    fi

    if ! awk '
      /- name: Upload dSYMs to Sentry/ { in_step=1; next }
      in_step && /^[[:space:]]*- name:/ { in_step=0 }
      in_step && /SENTRY_CLI="\$\(\.\/scripts\/ensure-sentry-cli\.sh\)"/ { saw_helper=1 }
      in_step && /"\$SENTRY_CLI" debug-files upload --include-sources/ { saw_upload=1 }
      END { exit !(saw_helper && saw_upload) }
    ' "$file"; then
      echo "FAIL: $(basename "$file") must install sentry-cli through scripts/ensure-sentry-cli.sh before dSYM upload"
      exit 1
    fi
  done

  echo "PASS: dSYM upload installs sentry-cli without requiring Homebrew"
}

check_sentry_cli_helper_behavior() {
  local helper="$ROOT_DIR/scripts/ensure-sentry-cli.sh"
  local tmp_dir bin_dir stdout stderr expected_path
  tmp_dir="$(mktemp -d)"
  bin_dir="$tmp_dir/bin"
  stdout="$tmp_dir/stdout"
  stderr="$tmp_dir/stderr"
  expected_path="$tmp_dir/runner/sentry-cli-bin/sentry-cli"
  mkdir -p "$bin_dir"

  cat > "$bin_dir/sentry-cli" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "ambient sentry-cli should not run" >&2
exit 44
EOF
  chmod +x "$bin_dir/sentry-cli"
  cat > "$bin_dir/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
output=""
while [[ $# -gt 0 ]]; do
	case "$1" in
		--output)
			output="$2"
			shift 2
			;;
		*)
			shift
			;;
	esac
done
if [[ -z "$output" ]]; then
	echo "missing --output" >&2
	exit 1
fi
cat > "$output" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
echo "sentry-cli 3.3.0"
SCRIPT
EOF
  chmod +x "$bin_dir/curl"
  cat > "$bin_dir/shasum" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
last=""
for arg in "$@"; do
	last="$arg"
done
printf 'dcede3b42632886a32753ad9d763f785d46afd5fa4580b5c979aad2d465d1cf5  %s\n' "$last"
EOF
  chmod +x "$bin_dir/shasum"

  if ! RUNNER_TEMP="$tmp_dir/runner" PATH="$bin_dir:/usr/bin:/bin" "$helper" >"$stdout" 2>"$stderr"; then
    echo "FAIL: sentry-cli helper behavior test should install pinned CLI"
    cat "$stderr" >&2 || true
    exit 1
  fi

  if [[ "$(cat "$stdout")" != "$expected_path" ]]; then
    echo "FAIL: sentry-cli helper must print only the executable path on stdout"
    exit 1
  fi

  if ! grep -Fq 'Installing sentry-cli 3.3.0 into' "$stderr"; then
    echo "FAIL: sentry-cli helper should report pinned install on stderr"
    exit 1
  fi
  if grep -Fq 'ambient sentry-cli should not run' "$stderr"; then
    echo "FAIL: sentry-cli helper must ignore ambient sentry-cli on PATH"
    exit 1
  fi

  rm -rf "$tmp_dir"
  echo "PASS: sentry-cli helper installs the pinned binary without ambient PATH state"
}

check_dmg_signing_uses_build_keychain() {
  local nightly_workflow="$ROOT_DIR/.github/workflows/nightly.yml"
  local nightly_helper="$ROOT_DIR/scripts/ci/notarize-nightly-dmg.sh"
  local release_workflow="$ROOT_DIR/.github/workflows/release.yml"

  if ! grep -Fq './scripts/ci/notarize-nightly-dmg.sh \' "$nightly_workflow"; then
    echo "FAIL: nightly workflow must invoke the guarded notarization helper"
    exit 1
  fi
  for needle in \
    'CODESIGN_TOOL="${CMUX_CODESIGN_TOOL:-/usr/bin/codesign}"' \
    '"$CREATE_DMG_TOOL" --no-code-sign "$APP_PATH" "$DMG_TMP_DIR"' \
    '"$CODESIGN_TOOL" --force --timestamp --keychain build.keychain' \
    '--sign "$APPLE_SIGNING_IDENTITY"' \
    '"$CODESIGN_TOOL" --verify --verbose=2 "$DMG_RELEASE"' \
    '"$XCRUN_TOOL" notarytool submit "$DMG_RELEASE"'; do
    if ! grep -Fq -- "$needle" "$nightly_helper"; then
      echo "FAIL: nightly notarization helper must sign the DMG through build.keychain before submission: $needle"
      exit 1
    fi
  done

  if grep -Eq -- '--identity([=[:space:]]|$)' "$release_workflow"; then
    echo "FAIL: release.yml must not let create-dmg codesign outside build.keychain"
    exit 1
  fi
  if ! awk '
    /create-dmg[[:space:]]*\\/ { in_dmg=1; next }
    in_dmg && /--no-code-sign[[:space:]]*\\/ { saw_no_code_sign=1 }
    in_dmg && /\/usr\/bin\/codesign --force --timestamp --keychain build\.keychain/ { saw_keychain=1 }
    in_dmg && /--sign "\$APPLE_SIGNING_IDENTITY"/ { saw_identity=1 }
    in_dmg && /\/usr\/bin\/codesign --verify --verbose=2 "\$(DMG_RELEASE|dmg_release)"/ { saw_verify=1 }
    in_dmg && /xcrun notarytool submit "\$(DMG_RELEASE|dmg_release)"/ { saw_notary=1 }
    END { exit !(saw_no_code_sign && saw_keychain && saw_identity && saw_verify && saw_notary) }
  ' "$release_workflow"; then
    echo "FAIL: release.yml must sign DMGs explicitly with build.keychain before notarization"
    exit 1
  fi

  echo "PASS: DMG signing uses build.keychain explicitly"
}

check_create_dmg_uses_run_local_npm_prefix() {
  for file in "$ROOT_DIR/.github/workflows/nightly.yml" "$ROOT_DIR/.github/workflows/release.yml"; do
    if ! awk '
      /- name: Install build deps/ { in_step=1; next }
      in_step && /^[[:space:]]*- name:/ { in_step=0 }
      in_step && /CMUX_NODE_BIN="\$\(command -v node\)"/ { saw_node=1 }
      in_step && /export npm_config_prefix="\$RUNNER_TEMP\/npm-global"/ { saw_prefix=1 }
      in_step && /mkdir -p "\$npm_config_prefix"/ { saw_mkdir=1 }
      in_step && /npm install --global "create-dmg@\$\{CREATE_DMG_VERSION\}"/ { saw_install=1 }
      in_step && /wrapper_dir="\$RUNNER_TEMP\/create-dmg-wrapper"/ { saw_wrapper=1 }
      in_step && /exec "\$CMUX_NODE_BIN" "\$npm_config_prefix\/lib\/node_modules\/create-dmg\/cli\.js" "\\\$@"/ { saw_exec=1 }
      in_step && /echo "\$wrapper_dir" >> "\$GITHUB_PATH"/ { saw_path=1 }
      END { exit !(saw_node && saw_prefix && saw_mkdir && saw_install && saw_wrapper && saw_exec && saw_path) }
    ' "$file"; then
      echo "FAIL: $(basename "$file") must run create-dmg from a setup-node-bound wrapper in a run-local npm prefix"
      exit 1
    fi
  done

  echo "PASS: create-dmg uses setup-node-bound wrapper from run-local npm prefix"
}

check_gui_smoke_unsupported_launch_handling() {
  local helper="$ROOT_DIR/scripts/smoke-launch-macos-app.sh"
  for needle in \
    'ALLOW_UNSUPPORTED_GUI="${CMUX_SMOKE_ALLOW_UNSUPPORTED_GUI:-0}"' \
    'DIRECT_EXEC="${CMUX_SMOKE_DIRECT_EXEC:-0}"' \
    'CMUX_UI_TEST_MODE="${CMUX_UI_TEST_MODE:-1}"' \
    'open_log_indicates_unsupported_gui()' \
    "grep -Fq 'OSLaunchdErrorDomain Code=125'" \
    "grep -Fq 'Domain does not support specified action'" \
    'GUI launch smoke unsupported on this runner'; do
    if ! grep -Fq -- "$needle" "$helper"; then
      echo "FAIL: smoke-launch helper must explicitly detect unsupported GUI launch: $needle"
      exit 1
    fi
  done

  if ! awk '
    /scripts\/smoke-launch-macos-app\.sh/ && /CMUX_SMOKE_ALLOW_UNSUPPORTED_GUI=1/ { saw_launchservices=1 }
    /scripts\/smoke-launch-macos-app\.sh/ && /CMUX_SMOKE_DIRECT_EXEC=1/ { saw_direct_exec=1 }
    END { exit !(saw_launchservices && saw_direct_exec) }
  ' "$ROOT_DIR/.github/workflows/release.yml"; then
    echo "FAIL: release signing smoke must run LaunchServices smoke before direct exec CI launch mode"
    exit 1
  fi

  local nightly_workflow="$ROOT_DIR/.github/workflows/nightly.yml"
  local nightly_helper="$ROOT_DIR/scripts/ci/notarize-nightly-dmg.sh"
  if ! grep -Fq './scripts/ci/notarize-nightly-dmg.sh \' "$nightly_workflow"; then
    echo "FAIL: nightly workflow must invoke the helper that owns launch smokes"
    exit 1
  fi
  for needle in \
    'SMOKE_TOOL="${CMUX_SMOKE_TOOL:-$ROOT_DIR/scripts/smoke-launch-macos-app.sh}"' \
    'CMUX_SMOKE_ALLOW_UNSUPPORTED_GUI=1 CMUX_SMOKE_DEBUG_LOGS=1 "$SMOKE_TOOL"' \
    'CMUX_SMOKE_DIRECT_EXEC=1 CMUX_SMOKE_DEBUG_LOGS=1 "$SMOKE_TOOL"'; do
    if ! grep -Fq -- "$needle" "$nightly_helper"; then
      echo "FAIL: nightly notarization helper must preserve both launch smokes: $needle"
      exit 1
    fi
  done

  if ! grep -Fq 'scripts/smoke-launch-macos-app.sh' "$ROOT_DIR/.github/workflows/release.yml"; then
    echo "FAIL: release.yml signing workflow must run launch smoke"
    exit 1
  fi

  echo "PASS: signing smoke handles unsupported GUI launch and release direct exec explicitly"
}

check_no_ci_xctest_skips() {
  if grep -nE '(^|[[:space:]])-skip-testing:' "$CI_FILE"; then
    echo "FAIL: ci.yml must not exclude individual XCTest methods with -skip-testing; fix or isolate the flaky test instead"
    exit 1
  fi

  echo "PASS: ci.yml does not exclude XCTest methods"
}

check_no_ci_swift_package_skips() {
  if grep -nE '(^|[[:space:]])swift[[:space:]]+test([[:space:]].*)?[[:space:]]--skip([[:space:]]|$)' "$CI_FILE"; then
    echo "FAIL: ci.yml must not exclude Swift package tests with swift test --skip; fix or isolate the failing package test instead"
    exit 1
  fi

  echo "PASS: ci.yml does not exclude Swift package tests"
}

check_web_db_behavior_tests() {
  local db_runner="$ROOT_DIR/web/scripts/run-db-behavior-tests.sh"
  if [[ ! -x "$db_runner" ]]; then
    echo "FAIL: web DB behavior runner must exist and be executable"
    exit 1
  fi

  if ! grep -Fq '"test:db:behavior": "bash scripts/run-db-behavior-tests.sh"' "$ROOT_DIR/web/package.json"; then
    echo "FAIL: web/package.json must expose test:db:behavior for DB-gated web tests"
    exit 1
  fi

  if ! awk '
    /- name: Database behavior tests/ { in_step=1; next }
    in_step && /^[[:space:]]*- name:/ { in_step=0 }
    in_step && /CMUX_DB_TEST:[[:space:]]*"1"/ { saw_env=1 }
    in_step && /bun run test:db:behavior/ { saw_runner=1 }
    END { exit !(saw_env && saw_runner) }
  ' "$CI_FILE"; then
    echo "FAIL: ci.yml must run the DB behavior test discovery runner with CMUX_DB_TEST=1"
    exit 1
  fi

  if ! grep -Fq 'grep -q "process\\.env\\.CMUX_DB_TEST"' "$db_runner"; then
    echo "FAIL: DB behavior runner must discover CMUX_DB_TEST-gated files instead of hard-coding a subset"
    exit 1
  fi

  echo "PASS: web DB behavior tests run through the discovery runner"
}

check_web_test_runner_behavior() {
  local fixture_dir fixture_runner args_log expected_args live_mode
  fixture_dir="$(mktemp -d)"
  trap 'rm -rf -- "$fixture_dir"' EXIT
  fixture_runner="$fixture_dir/web/scripts/run-tests.sh"
  args_log="$fixture_dir/bun-args.log"
  mkdir -p \
    "$fixture_dir/web/.hidden" \
    "$fixture_dir/web/node_modules/fixture" \
    "$fixture_dir/web/scripts" \
    "$fixture_dir/web/tests/nested" \
    "$fixture_dir/bin"
  cp "$ROOT_DIR/web/scripts/run-tests.sh" "$fixture_runner"
  touch \
    "$fixture_dir/web/.hidden/ignored.test.ts" \
    "$fixture_dir/web/node_modules/fixture/ignored.test.ts" \
    "$fixture_dir/web/scripts/alpha_spec.mts" \
    "$fixture_dir/web/tests/beta.test.ts" \
    "$fixture_dir/web/tests/nested/gamma_test.tsx" \
    "$fixture_dir/web/tests/nested/omega.spec.mjs"

  cat > "$fixture_dir/bin/bun" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--version" ]]; then
  printf '%s\n' "${CMUX_WEB_TEST_RUNNER_BUN_VERSION:-1.3.14}"
  exit 0
fi
printf '%s\n' "$@" > "$CMUX_WEB_TEST_RUNNER_ARGS_LOG"
EOF
  chmod +x "$fixture_dir/bin/bun"

  if ! PATH="$fixture_dir/bin:/usr/bin:/bin" \
    CMUX_WEB_TEST_RUNNER_ARGS_LOG="$args_log" \
    /bin/bash "$fixture_runner"; then
    rm -rf "$fixture_dir"
    echo "FAIL: shared web test runner default discovery should execute"
    exit 1
  fi

  expected_args=$'test\n--isolate\n./scripts/alpha_spec.mts\n./tests/beta.test.ts\n./tests/nested/gamma_test.tsx\n./tests/nested/omega.spec.mjs'
  if [[ "$(cat "$args_log")" != "$expected_args" ]]; then
    echo "FAIL: shared web test runner must sort recursive Bun test patterns and exclude hidden dependencies"
    cat "$args_log"
    rm -rf "$fixture_dir"
    exit 1
  fi

  if PATH="$fixture_dir/bin:/usr/bin:/bin" \
    CMUX_WEB_TEST_RUNNER_ARGS_LOG="$args_log" \
    CMUX_WEB_TEST_RUNNER_BUN_VERSION="1.2.14" \
    /bin/bash "$fixture_runner" >/dev/null 2>&1; then
    echo "FAIL: shared web test runner must reject Bun versions with process-global mock leakage"
    rm -rf "$fixture_dir"
    exit 1
  fi

  if PATH="$fixture_dir/bin:/usr/bin:/bin" \
    CMUX_WEB_TEST_RUNNER_ARGS_LOG="$args_log" \
    CMUX_WEB_TEST_RUNNER_BUN_VERSION="1.3.13" \
    /bin/bash "$fixture_runner" >/dev/null 2>&1; then
    echo "FAIL: shared web test runner must enforce the patch-level Bun isolation boundary"
    rm -rf "$fixture_dir"
    exit 1
  fi

  if ! PATH="$fixture_dir/bin:/usr/bin:/bin" \
    CMUX_WEB_TEST_RUNNER_ARGS_LOG="$args_log" \
    /bin/bash "$fixture_runner" \
    --coverage -t "fixture runs" --bail=2 --parallel=2; then
    rm -rf "$fixture_dir"
    echo "FAIL: shared web test runner option-only discovery should execute"
    exit 1
  fi
  expected_args+=$'\n--coverage\n-t\nfixture runs\n--bail=2\n--parallel=2'
  if [[ "$(cat "$args_log")" != "$expected_args" ]]; then
    echo "FAIL: option-only runs must retain sorted discovery before forwarding options"
    cat "$args_log"
    rm -rf "$fixture_dir"
    exit 1
  fi

  if ! PATH="$fixture_dir/bin:/usr/bin:/bin" \
    CMUX_WEB_TEST_RUNNER_ARGS_LOG="$args_log" \
    /bin/bash "$fixture_runner" --changed=main; then
    rm -rf "$fixture_dir"
    echo "FAIL: shared web test runner changed-file discovery should execute"
    exit 1
  fi
  expected_args=$'test\n--isolate\n--changed=main'
  if [[ "$(cat "$args_log")" != "$expected_args" ]]; then
    echo "FAIL: changed-file selection must retain Bun-owned discovery"
    cat "$args_log"
    rm -rf "$fixture_dir"
    exit 1
  fi

  if ! PATH="$fixture_dir/bin:/usr/bin:/bin" \
    CMUX_WEB_TEST_RUNNER_ARGS_LOG="$args_log" \
    /bin/bash "$fixture_runner" tests/beta; then
    rm -rf "$fixture_dir"
    echo "FAIL: shared web test runner explicit filter should execute"
    exit 1
  fi
  expected_args=$'test\n--isolate\ntests/beta'
  if [[ "$(cat "$args_log")" != "$expected_args" ]]; then
    echo "FAIL: explicit test filters must remain scoped instead of expanding to every test"
    cat "$args_log"
    rm -rf "$fixture_dir"
    exit 1
  fi

  if ! PATH="$fixture_dir/bin:/usr/bin:/bin" \
    CMUX_WEB_TEST_RUNNER_ARGS_LOG="$args_log" \
    /bin/bash "$fixture_runner" --bail tests/beta; then
    rm -rf "$fixture_dir"
    echo "FAIL: shared web test runner optional flag plus filter should execute"
    exit 1
  fi
  expected_args=$'test\n--isolate\n--bail\ntests/beta'
  if [[ "$(cat "$args_log")" != "$expected_args" ]]; then
    echo "FAIL: optional-valued flags must not consume a following test filter"
    cat "$args_log"
    rm -rf "$fixture_dir"
    exit 1
  fi

  for live_mode in --watch --hot; do
    if ! PATH="$fixture_dir/bin:/usr/bin:/bin" \
      CMUX_WEB_TEST_RUNNER_ARGS_LOG="$args_log" \
      /bin/bash "$fixture_runner" "$live_mode"; then
      rm -rf "$fixture_dir"
      echo "FAIL: shared web test runner $live_mode mode should execute"
      exit 1
    fi
    expected_args=$'test\n--isolate\n'"$live_mode"
    if [[ "$(cat "$args_log")" != "$expected_args" ]]; then
      echo "FAIL: $live_mode mode must delegate live test discovery to Bun"
      cat "$args_log"
      rm -rf "$fixture_dir"
      exit 1
    fi
  done

  cat > "$fixture_dir/web/bunfig.toml" <<'EOF'
[test]
root = "tests"
EOF
  if ! PATH="$fixture_dir/bin:/usr/bin:/bin" \
    CMUX_WEB_TEST_RUNNER_ARGS_LOG="$args_log" \
    /bin/bash "$fixture_runner"; then
    rm -rf "$fixture_dir"
    echo "FAIL: shared web test runner configured-root discovery should execute"
    exit 1
  fi
  expected_args=$'test\n--isolate'
  if [[ "$(cat "$args_log")" != "$expected_args" ]]; then
    echo "FAIL: default root-bearing Bun config must retain Bun-owned discovery"
    cat "$args_log"
    rm -rf "$fixture_dir"
    exit 1
  fi
  rm -f "$fixture_dir/web/bunfig.toml"

  if ! PATH="$fixture_dir/bin:/usr/bin:/bin" \
    CMUX_WEB_TEST_RUNNER_ARGS_LOG="$args_log" \
    /bin/bash "$fixture_runner" --config=ci.bunfig.toml; then
    rm -rf "$fixture_dir"
    echo "FAIL: shared web test runner alternate-config discovery should execute"
    exit 1
  fi
  expected_args=$'test\n--isolate\n--config=ci.bunfig.toml'
  if [[ "$(cat "$args_log")" != "$expected_args" ]]; then
    echo "FAIL: alternate Bun configs must retain Bun-owned discovery"
    cat "$args_log"
    rm -rf "$fixture_dir"
    exit 1
  fi

  cat > "$fixture_dir/bin/find" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "./tests/beta.test.ts"
exit 1
EOF
  chmod +x "$fixture_dir/bin/find"
  rm -f "$args_log"
  if PATH="$fixture_dir/bin:/usr/bin:/bin" \
    CMUX_WEB_TEST_RUNNER_ARGS_LOG="$args_log" \
    /bin/bash "$fixture_runner" \
    >"$fixture_dir/discovery.stdout" 2>"$fixture_dir/discovery.stderr"; then
    echo "FAIL: shared web test runner must reject partial discovery results"
    rm -rf "$fixture_dir"
    exit 1
  fi
  if ! grep -Fq "Web test discovery failed" "$fixture_dir/discovery.stderr"; then
    echo "FAIL: shared web test runner must explain discovery failures"
    cat "$fixture_dir/discovery.stderr"
    rm -rf "$fixture_dir"
    exit 1
  fi
  if [[ -e "$args_log" ]]; then
    echo "FAIL: shared web test runner must not execute Bun after discovery fails"
    cat "$args_log"
    rm -rf "$fixture_dir"
    exit 1
  fi
  rm -f "$fixture_dir/bin/find"

  mkdir -p "$fixture_dir/empty/scripts"
  cp "$ROOT_DIR/web/scripts/run-tests.sh" "$fixture_dir/empty/scripts/run-tests.sh"
  if ! PATH="$fixture_dir/bin:/usr/bin:/bin" \
    CMUX_WEB_TEST_RUNNER_ARGS_LOG="$args_log" \
    /bin/bash "$fixture_dir/empty/scripts/run-tests.sh" \
    --pass-with-no-tests; then
    rm -rf "$fixture_dir"
    echo "FAIL: shared web test runner must honor --pass-with-no-tests"
    exit 1
  fi
  expected_args=$'test\n--isolate\n--pass-with-no-tests'
  if [[ "$(cat "$args_log")" != "$expected_args" ]]; then
    echo "FAIL: --pass-with-no-tests must retain Bun-owned empty discovery"
    cat "$args_log"
    rm -rf "$fixture_dir"
    exit 1
  fi

  if PATH="$fixture_dir/bin:/usr/bin:/bin" \
    CMUX_WEB_TEST_RUNNER_ARGS_LOG="$args_log" \
    /bin/bash "$fixture_dir/empty/scripts/run-tests.sh" \
    >"$fixture_dir/empty.stdout" 2>"$fixture_dir/empty.stderr"; then
    rm -rf "$fixture_dir"
    echo "FAIL: shared web test runner must fail when no tests exist"
    exit 1
  fi
  if ! grep -Fq "No web test files found" "$fixture_dir/empty.stderr"; then
    echo "FAIL: shared web test runner must explain an empty test suite"
    cat "$fixture_dir/empty.stderr"
    rm -rf "$fixture_dir"
    exit 1
  fi

  rm -rf "$fixture_dir"
  trap - EXIT
  echo "PASS: shared web test runner sorts recursive discovery and fails closed when empty"
}

check_tmux_terminal_nightly_isolation() {
  check_macos_runner "$TMUX_CORPUS_FILE" "terminal-nightly"

  if ! awk '
    /^  terminal-nightly:/ { in_job=1; next }
    in_job && /^  [^[:space:]#][^:]*:[[:space:]]*(#.*)?$/ { in_job=0 }
    in_job && /CMUX_DERIVED_DATA_PATH/ { saw_env=1 }
    in_job && /-derivedDataPath "\$CMUX_DERIVED_DATA_PATH"/ { saw_flag=1 }
    in_job && /scripts\/ci\/xcodebuild_noninteractive\.py/ { saw_noninteractive=1 }
    in_job && /SWIFT_BACKTRACE: "interactive=no,timeout=0s,symbolicate=off,color=no"/ { saw_backtrace=1 }
    in_job && /All failures are expected, treating as pass/ { saw_expected_failure_handling=1 }
    END { exit !(saw_env && saw_flag && saw_noninteractive && saw_backtrace && saw_expected_failure_handling) }
  ' "$TMUX_CORPUS_FILE"; then
    echo "FAIL: tmux corpus terminal-nightly must use isolated DerivedData, the noninteractive xcodebuild wrapper, and expected-failure handling"
    exit 1
  fi

  echo "PASS: tmux corpus terminal-nightly uses isolated DerivedData, noninteractive xcodebuild, and expected-failure handling"
}

check_no_bare_github_hosted_runners() {
  # Every job must route its runner through a repo variable (LINUX_RUNNER,
  # MACOS_RUNNER_*) so the Blacksmith<->Warp / Blacksmith<->macos-26 overflow
  # switch is a single repo-variable flip with no PR. A bare GitHub-hosted
  # label (ubuntu-*, macos-NN) cannot be redirected, so it is forbidden.
  # Bare paid-provider labels (blacksmith-*, warp-*, depot-*) stay allowed for
  # deliberate single-runner pins such as the testmanagerd-wedged
  # `app-host-unit-tests` job.
  local hits
  hits="$(grep -rnE "runs-on:[[:space:]]*(ubuntu-[a-z0-9.]+|macos-[a-z0-9]+)([[:space:]]*$|[[:space:]]+#)" "$ROOT_DIR/.github/workflows" | grep -v "github-hosted-required" || true)"
  if [[ -n "$hits" ]]; then
    echo "FAIL: these jobs use a bare GitHub-hosted runner; route them through vars.LINUX_RUNNER / vars.MACOS_RUNNER_IOS so Blacksmith<->overflow stays a repo-variable flip:"
    echo "$hits"
    exit 1
  fi
  echo "PASS: no workflow pins a bare GitHub-hosted runner; all route through runner repo variables"
}

check_no_self_hosted_fleet_runners() {
  # Required jobs route through repository variables. Forbid hardcoded fleet
  # labels so Tart cutover and paid-provider fallback remain configuration
  # changes and a physical host label cannot bypass the isolated VM pool.
  # Allowed macOS labels (none carried by any fleet runner):
  #   blacksmith-{6,12}vcpu-macos-{15,26,latest}, warp-macos-15-arm64-6x,
  #   depot-macos-{latest,14}.
  # NOTE: reload-build.yml is the dev-build offload path (workflow_dispatch,
  # not required CI) and intentionally targets the fleet via a free-form input;
  # this guard only inspects runner-selection lines, not its input description.
  local fleet='macos-26|warp-macos-26-arm64-6x|cmux-aws-macos|cmux-macos|cmux-local-macos|macfleet|tart-[a-z0-9-]+|(^|[^a-z0-9-])mac4([^a-z0-9]|$)|(^|[^a-z0-9-])mac-mini([^a-z0-9]|$)|slot-[0-9]|xcode-[0-9]+-[0-9]|(^|[^a-z0-9-])cmux([^a-z0-9-]|$)'
  local allowed='blacksmith-(6|12)vcpu-macos-(15|26|latest)|warp-macos-15-arm64-6x|depot-macos-(latest|14)'

  # Bare self-hosted/macOS/ARM64 targeting (inline array or multi-line list).
  # Case-sensitive: GitHub's auto labels are `macOS`/`ARM64`, distinct from the
  # lowercase `macos`/`arm64` inside cloud labels like warp-macos-15-arm64-6x.
  local selfhosted='(^|[^A-Za-z0-9_-])(self-hosted|macOS|ARM64)([^A-Za-z0-9_-]|$)'
  local forbidden="${fleet}|${selfhosted}"

  # Self-test the matcher so a future edit cannot silently narrow it: every
  # known fleet/self-hosted label must be caught, every allowed cloud label
  # must pass. Probes are raw YAML values (no path:lineno: prefix).
  local probe
  for probe in 'runs-on: macfleet' '- tart-canary' '- tart-dual' '- tart-small' '- tart-macos-26' '- tart-ios' '- mac4' '- mac-mini' '- slot-3' '- xcode-26-3' '- cmux' \
               "runs-on: \${{ vars.X || 'macos-26' }}" '- warp-macos-26-arm64-6x' \
               '- cmux-aws-macos-15' '- cmux-macos-26' '- self-hosted' '- macOS' '- ARM64' \
               'runs-on: [self-hosted, macOS, ARM64]'; do
    if ! printf '%s\n' "$probe" | grep -Eq "($forbidden)"; then
      echo "FAIL: fleet-runner guard self-test missed a known fleet/self-hosted label: $probe"
      exit 1
    fi
  done
  for probe in "runs-on: \${{ vars.X || 'blacksmith-6vcpu-macos-26' }}" \
               "runs-on: \${{ vars.X || 'blacksmith-12vcpu-macos-26' }}" \
               "runs-on: \${{ vars.MACOS_RUNNER_15 || 'warp-macos-15-arm64-6x' }}" \
               '- warp-macos-15-arm64-6x' '- depot-macos-latest' '- blacksmith-6vcpu-macos-15' \
               '- blacksmith-4vcpu-ubuntu-2404'; do
    if printf '%s\n' "$probe" | sed -E "s/($allowed)//g" | grep -Eq "($forbidden)"; then
      echo "FAIL: fleet-runner guard self-test false-positived a cloud label: $probe"
      exit 1
    fi
  done

  probe="runs-on: \${{ vars.USE_TART == '1' && 'tart-canary' || 'blacksmith-6vcpu-macos-15' }}"
  if ! printf '%s\n' "$probe" | sed -E "s/($allowed)//g" | grep -Eq "($forbidden)"; then
    echo "FAIL: fleet-runner guard self-test let an allowed fallback mask a forbidden label: $probe"
    exit 1
  fi

  local e2e_tart_option_line e2e_tart_dual_option_line e2e_tart_small_option_line e2e_tart_tahoe_option_line ios_tart_option_line
  e2e_tart_option_line="$(awk '
    /^      runner:$/ { in_runner=1; next }
    in_runner && /^      [A-Za-z0-9_-]+:/ { in_runner=0; in_options=0 }
    in_runner && /^        options:$/ { in_options=1; next }
    in_options && /^        [A-Za-z0-9_-]+:/ { in_options=0 }
    in_options && /^          - tart-canary$/ { print FNR }
  ' "$E2E_FILE")"
  e2e_tart_dual_option_line="$(awk '
    /^      runner:$/ { in_runner=1; next }
    in_runner && /^      [A-Za-z0-9_-]+:/ { in_runner=0; in_options=0 }
    in_runner && /^        options:$/ { in_options=1; next }
    in_options && /^        [A-Za-z0-9_-]+:/ { in_options=0 }
    in_options && /^          - tart-dual$/ { print FNR }
  ' "$E2E_FILE")"
  e2e_tart_small_option_line="$(awk '
    /^      runner:$/ { in_runner=1; next }
    in_runner && /^      [A-Za-z0-9_-]+:/ { in_runner=0; in_options=0 }
    in_runner && /^        options:$/ { in_options=1; next }
    in_options && /^        [A-Za-z0-9_-]+:/ { in_options=0 }
    in_options && /^          - tart-small$/ { print FNR }
  ' "$E2E_FILE")"
  ios_tart_option_line="$(awk '
    /^      runner:$/ { in_runner=1; next }
    in_runner && /^      [A-Za-z0-9_-]+:/ { in_runner=0; in_options=0 }
    in_runner && /^        options:$/ { in_options=1; next }
    in_options && /^        [A-Za-z0-9_-]+:/ { in_options=0 }
    in_options && /^          - tart-ios$/ { print FNR }
  ' "$IOS_FILE")"

  local hits="" line content content_without_allowed
  # Inspect runner-selection lines only: runs-on:, matrix `os:`, and scalar list
  # items (`  - <label>`, which covers dispatch runner dropdowns and multi-line
  # `runs-on:` arrays). `- name:` / `- uses:` step entries have a colon and are
  # excluded. grep matches against file CONTENT; strip the `path:lineno:` prefix
  # before matching the value so the checkout path (which contains "cmux") can
  # never match the bare `cmux` label.
  while IFS= read -r line; do
    content="${line#*:*:}"
    content_without_allowed="$(printf '%s\n' "$content" | sed -E "s/($allowed)//g")"
    printf '%s\n' "$content_without_allowed" | grep -Eq "($forbidden)" || continue
    if [[ -n "$e2e_tart_option_line" ]] && [[ "$line" == "$E2E_FILE:$e2e_tart_option_line:"* ]]; then
      continue
    fi
    if [[ -n "$e2e_tart_dual_option_line" ]] && [[ "$line" == "$E2E_FILE:$e2e_tart_dual_option_line:"* ]]; then
      continue
    fi
    if [[ -n "$e2e_tart_small_option_line" ]] && [[ "$line" == "$E2E_FILE:$e2e_tart_small_option_line:"* ]]; then
      continue
    fi
    if [[ -n "$ios_tart_option_line" ]] && [[ "$line" == "$IOS_FILE:$ios_tart_option_line:"* ]]; then
      continue
    fi
    hits+="$line"$'\n'
  done < <(grep -rnE "(runs-on:|[[:space:]]os:[[:space:]]|^[[:space:]]*-[[:space:]]+[A-Za-z0-9._-]+[[:space:]]*$)" "$ROOT_DIR/.github/workflows")
  if [[ -n "$hits" ]]; then
    echo "FAIL: workflow references a self-hosted mac fleet label or bare self-hosted runner in a runner-selection position."
    echo "      Use a cloud label so required jobs never land on a mini that can't foreground a GUI app:"
    echo "      blacksmith-{6,12}vcpu-macos-{15,26,latest} / warp-macos-15-arm64-6x / depot-macos-{latest,14}."
    echo "$hits"
    exit 1
  fi
  echo "PASS: no workflow can route a required job to a self-hosted mac fleet runner (cloud only)"
}

# ci.yml jobs
check_runner "$CI_FILE" "app-host-unit-tests" 'runs-on: blacksmith-6vcpu-macos-15' "Blacksmith macos-15"
check_runner "$CI_FILE" "tests-build-and-lag" 'runs-on: blacksmith-6vcpu-macos-15' "Blacksmith macos-15"
check_runner "$CI_FILE" "release-build" 'runs-on: blacksmith-6vcpu-macos-26' "Blacksmith macos-26"
check_runner "$CI_FILE" "ui-regressions" 'runs-on: blacksmith-6vcpu-macos-15' "Blacksmith macos-15"

# build-ghosttykit.yml
check_runner "$GHOSTTYKIT_FILE" "build-ghosttykit" 'runs-on: blacksmith-6vcpu-macos-15' "Blacksmith macos-15"

# ci-macos-compat.yml uses matrix.os.
check_runner "$COMPAT_FILE" "compat-tests" 'os: blacksmith-6vcpu-macos-15' "Blacksmith macos-15"

# test-e2e.yml is manual, so keep the Depot GUI runner choices but cancel
# duplicate queued runs for the same ref/filter/runner.
check_e2e_runner_fallbacks
check_ios_tart_canary

check_xcode_selection
check_release_build_signal
check_release_build_disk_cleanup
check_release_helper_artifact_from_package_lane
check_runtime_regressions_collapsed
check_signing_intermediate_imports
check_signing_intermediate_helper_behavior
check_sentry_cli_install_portability
check_sentry_cli_helper_behavior
check_dmg_signing_uses_build_keychain
check_create_dmg_uses_run_local_npm_prefix
check_gui_smoke_unsupported_launch_handling
check_no_ci_xctest_skips
check_no_ci_swift_package_skips
check_web_db_behavior_tests
check_web_test_runner_behavior
check_tmux_terminal_nightly_isolation
