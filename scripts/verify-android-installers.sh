#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
termux_installer="$repo_root/scripts/install-termux.sh"
linux_installer="$repo_root/scripts/install-android-linux.sh"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

for installer in "$termux_installer" "$linux_installer"; do
  bash -n "$installer"
  printf 'PASS bash syntax: %s\n' "${installer#"$repo_root"/}"
done

expect_rejection() {
  local name="$1"
  local expected="$2"
  shift 2
  local output="$tmp/$name.log"
  local status=0

  "$@" >"$output" 2>&1 || status=$?
  if [ "$status" -eq 0 ]; then
    printf 'FAIL %s: installer unexpectedly succeeded\n' "$name" >&2
    cat "$output" >&2
    return 1
  fi
  if ! grep -Fq -- "$expected" "$output"; then
    printf 'FAIL %s: expected diagnostic not found: %s\n' "$name" "$expected" >&2
    cat "$output" >&2
    return 1
  fi
  printf 'PASS fail-fast guard: %s (exit %s)\n' "$name" "$status"
}

# A normal Linux shell must never be mistaken for the official Termux app.
expect_rejection \
  "termux-host-guard" \
  "run this inside the official Termux app" \
  env PREFIX=/usr bash "$termux_installer"

# The Android Linux installer is deliberately limited to ARM64 guests.
# CI runs on x86_64, so it must stop before installing packages or changing
# the host. The script's diagnostic is part of its supported interface.
expect_rejection \
  "linux-architecture-guard" \
  "unsupported guest architecture" \
  bash "$linux_installer"

printf '\nAndroid installer checks passed. No packages were installed.\n'
