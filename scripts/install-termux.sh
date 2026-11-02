#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

fail() {
  printf 'REA Pixel/Termux installer: %s\n' "$1" >&2
  exit 1
}

# This path is for the official Termux app on Android, not proot or desktop Linux.
case "${PREFIX:-}" in
  /data/data/com.termux/files/usr) ;;
  *) fail "run this inside the official Termux app; PREFIX is not the Termux prefix." ;;
esac

[ "$(id -u)" -ne 0 ] || fail "do not run as root. Termux packages and npm globals belong to the app user."
[ -f package.json ] || fail "run this script from the root of the rea-android source checkout."
[ -f package-lock.json ] || fail "package-lock.json is missing; use a complete source checkout."
command -v pkg >/dev/null 2>&1 || fail "Termux pkg is unavailable."

# Pixel phones use 64-bit ARM. Fail early rather than building on an unsupported ABI.
device_arch="$(uname -m)"
case "$device_arch" in
  aarch64|arm64) ;;
  *) fail "unsupported Android ABI '$device_arch'; this installer targets 64-bit ARM (aarch64), as used by Pixel devices." ;;
esac

android_model="$(getprop ro.product.model 2>/dev/null || true)"
android_release="$(getprop ro.build.version.release 2>/dev/null || true)"
android_sdk="$(getprop ro.build.version.sdk 2>/dev/null || true)"
android_abi="$(getprop ro.product.cpu.abi 2>/dev/null || true)"
printf 'Device: %s\n' "${android_model:-unknown Android device}"
printf 'Android: %s (API %s)\n' "${android_release:-unknown}" "${android_sdk:-unknown}"
printf 'ABI: %s / kernel arch: %s\n' "${android_abi:-unknown}" "$device_arch"
if [ -r /proc/meminfo ]; then
  awk '/MemTotal:/ { printf "RAM visible to Termux: %.1f GiB\n", $2 / 1048576 }' /proc/meminfo
fi
df -h "$HOME" 2>/dev/null | tail -n 1 || true

printf '\nUpdating Termux packages and installing build prerequisites...\n'
pkg update -y
pkg install -y nodejs-lts npm git x11-repo termux-exec

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
if (process.arch !== "arm64") {
  console.error("Expected 64-bit ARM Node.js for Pixel; got " + process.arch + ".");
  process.exit(1);
}
if (!supported) {
  console.error("Unsupported Node.js " + process.versions.node +
    ". REA requires 22.19+, 24.11+, or 26+ within those major lines.");
  process.exit(1);
}
'

# Match the repository's pinned npm version instead of whichever npm happens
# to be bundled with the current Termux nodejs-lts package.
package_manager="$(node -e 'const p=require("./package.json"); if (!p.packageManager) process.exit(1); process.stdout.write(p.packageManager)')"
toolchain="$HOME/.cache/rea-termux-toolchain"
mkdir -p "$toolchain"
printf '\nInstalling repository-pinned package manager: %s\n' "$package_manager"
npm install --prefix "$toolchain" --no-package-lock --ignore-scripts "$package_manager"
export PATH="$toolchain/node_modules/.bin:$PATH"

printf '\nRuntime: %s / %s\n' "$(node --version)" "$(npm --version)"
printf 'Building the Android/Termux distribution...\n'

# Build on-device: never reuse desktop or emulator native binaries.
npm ci --no-audit --no-fund
npm run build:termux

# Avoid a second desktop-oriented lifecycle build during global installation.
npm install --global --ignore-scripts .

command -v rea >/dev/null 2>&1 || fail "installation finished but rea is not on PATH."
printf '\nREA %s installed on Android/ARM64.\n' "$(rea --version)"
printf 'Next: rea setup\n'
printf 'Diagnostics: rea doctor --json\n'
