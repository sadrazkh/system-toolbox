#!/bin/sh
# Menu/launcher: uses local checkout files, or downloads only the selected tool.
set -eu
umask 077
usage() {
    printf 'System Toolbox\nUsage: sh toolbox.sh [--local] [dns|network|system|ports] [tool arguments]\nWithout arguments, an interactive menu is shown. --local uses a trusted local checkout.\n'
}
local_mode=0
if [ "${1:-}" = --local ]; then local_mode=1; shift; fi
case "${1:-}" in -h|--help) usage; exit 0;; esac
if [ "$#" = 0 ]; then
    printf 'System Toolbox\n1) DNS settings\n2) Network diagnostics\n3) System health\n4) Listening ports\n0) Exit\nChoice: '
    IFS= read -r selection || { usage; exit 1; }
    case "$selection" in 1) set -- dns;; 2) set -- network;; 3) set -- system;; 4) set -- ports;; 0) exit 0;; *) printf 'Unknown choice.\n' >&2; exit 1;; esac
fi
tool=$1
shift
case "$tool" in dns) relative='dns.sh';; network) relative='tools/network-check.sh';; system) relative='tools/system-check.sh';; ports) relative='tools/ports.sh';; *) usage; exit 1;; esac
local_dir=$(CDPATH='' cd -P "$(dirname "$0")" && pwd)
file="$local_dir/$relative"
if [ "$local_mode" = 1 ]; then
    [ -f "$file" ] || { printf 'Selected tool is missing from the local checkout.\n' >&2; exit 1; }
else
    temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/system-toolbox.XXXXXX")
    file="$temp_dir/tool.sh"
    trap 'rm -f "$file"; rmdir "$temp_dir"' EXIT
    url="https://raw.githubusercontent.com/sadrazkh/system-toolbox/main/$relative"
    if command -v curl >/dev/null 2>&1; then curl -fLsS --connect-timeout 10 --max-time 60 -o "$file" "$url"
    elif command -v wget >/dev/null 2>&1; then wget -q -T 30 -O "$file" "$url"
    else printf 'Install curl or wget to download a tool.\n' >&2; exit 1
    fi
fi
if [ "$tool" = dns ] && [ "$(id -u)" != 0 ]; then
    command -v sudo >/dev/null 2>&1 || { printf 'Run the DNS tool as root (sudo is unavailable).\n' >&2; exit 1; }
    sudo sh "$file" "$@"
else sh "$file" "$@"
fi
