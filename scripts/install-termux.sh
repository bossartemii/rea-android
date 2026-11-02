#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

fail() {
  printf 'REA Android installer: %s\n' "$1" >&2
  exit 1
}

# This installer intentionally targets Termux, not generic Android shells,
# proot distributions, or desktop Linux.
case "${PREFIX:-}" in
  /data/data/com.termux/files/usr) ;;
  *) fail "run this inside the official Termux app; PREFIX is not the Termux prefix." ;;
esac

[ "$(id -u)" -ne 0 ] || fail "do not run as root. Termux packages and npm globals belong to the app user."
[ -f package.json ] || fail "run this script from the root of the rea-android source checkout."
[ -f package-lock.json ] || fail "package-lock.json is missing; use a complete source checkout."

command -v pkg >/dev/null 2>&1 || fail "Termux pkg is unavailable."
printf 'Updating Termux packages and installing build prerequisites...\n'
pkg update -y
pkg install -y nodejs-lts npm git termux-exec

command -v node >/dev/null 2>&1 || fail "Node.js was not installed."
command -v npm >/dev/null 2>&1 || fail "npm was not installed."

node -e '
const [major, minor] = process.versions.node.split(".").map(Number);
const supported =
  (major === 22 && minor >= 19) ||
  (major === 24 && minor >= 11) ||
  major >= 26;
if (process.platform !== "android") {
  console.error("Expected Termux Android Node.js; got " + process.platform + ".");
  process.exit(1);
}
if (!supported) {
  console.error("Unsupported Node.js " + process.versions.node +
    ". REA requires 22.19+, 24.11+, or 26+ within those major lines.");
  process.exit(1);
}
'

printf 'Host: Android / Termux\n'
printf 'Node: %s\n' "$(node --version)"
printf 'npm:  %s\n' "$(npm --version)"

# Build the Android-compatible distribution from source. Do not install a
# desktop Node binary or copy native artifacts from another operating system.
npm ci
npm run build:termux

# The build has produced the package's distributable files. Skip lifecycle
# scripts here so npm cannot accidentally trigger a second desktop-oriented
# build during the global install.
npm install --global --ignore-scripts .

command -v rea >/dev/null 2>&1 || fail "installation finished but rea is not on PATH."
printf '\nREA %s installed for Termux.\n' "$(rea --version)"
printf 'Next: rea setup\n'
printf 'Diagnostics: rea doctor --json\n'
