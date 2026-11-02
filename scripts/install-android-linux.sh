#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'REA Android Linux VM installer: %s\n' "$1" >&2
  exit 1
}

[ "$(id -u)" -ne 0 ] || fail "run as your normal Linux user; sudo is used only for apt."
[ -f package.json ] && [ -f package-lock.json ] || fail "run from the root of a complete REA source checkout."
command -v apt-get >/dev/null 2>&1 || fail "this installer currently targets Debian/Ubuntu-based Linux guests."
[ -r /etc/os-release ] || fail "cannot identify Linux distribution."
. /etc/os-release
case "${ID:-}" in debian|ubuntu|linuxmint|pop) ;; *) fail "unsupported distribution '${ID:-unknown}'; Debian/Ubuntu guests only." ;; esac

arch="$(uname -m)"
case "$arch" in aarch64|arm64) ;; *) fail "unsupported guest architecture '$arch'; expected ARM64." ;; esac
if ! getconf GNU_LIBC_VERSION >/dev/null 2>&1; then
  fail "GNU glibc was not detected. This is not the Debian/glibc guest environment expected by this installer."
fi

printf 'Linux guest: %s %s\n' "${PRETTY_NAME:-$ID}" "${VERSION_ID:-}"
printf 'Architecture: %s; libc: %s\n' "$arch" "$(getconf GNU_LIBC_VERSION)"
printf 'Memory and storage visible to the guest:\n'
awk '/MemTotal:/ { printf "RAM: %.1f GiB\n", $2 / 1048576 }' /proc/meminfo 2>/dev/null || true
df -h "$HOME" 2>/dev/null | tail -n 1 || true

sudo -v
sudo apt-get update
sudo apt-get install -y ca-certificates curl git build-essential python3

# Install a supported Node 24 LTS runtime for the Linux/glibc guest. This is
# intentionally separate from Termux's Android/Bionic Node.js distribution.
curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
sudo apt-get install -y nodejs

command -v node >/dev/null 2>&1 || fail "Node.js installation failed."
node -e '
const [major, minor] = process.versions.node.split(".").map(Number);
const supported = (major === 22 && minor >= 19) ||
  (major === 24 && minor >= 11) || major >= 26;
if (process.platform !== "linux" || process.arch !== "arm64") {
  console.error("Expected Linux ARM64 Node.js; got " + process.platform + "/" + process.arch + ".");
  process.exit(1);
}
if (!supported) {
  console.error("Unsupported Node.js " + process.versions.node +
    ". REA requires 22.19+, 24.11+, or 26+ within those major lines.");
  process.exit(1);
}
'

package_manager="$(node -e 'const p=require("./package.json"); if (!p.packageManager) process.exit(1); process.stdout.write(p.packageManager)')"
toolchain="$HOME/.cache/rea-linux-toolchain"
mkdir -p "$toolchain"
npm install --prefix "$toolchain" --no-package-lock --ignore-scripts "$package_manager"
export PATH="$toolchain/node_modules/.bin:$PATH"

printf 'Runtime: %s / %s\n' "$(node --version)" "$(npm --version)"
npm ci --no-audit --no-fund
npm run build
npm install --global --ignore-scripts .

command -v rea >/dev/null 2>&1 || fail "installation completed but rea is not on PATH."
printf '\nREA %s installed in Linux ARM64 guest.\n' "$(rea --version)"
printf 'Next: rea setup\n'
printf 'Diagnostics: rea doctor --json\n'
