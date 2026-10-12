#!/bin/sh
# Read-only system health summary. Does not show command arguments or secrets.
set -u
LC_ALL=C
export LC_ALL
case "${1:-}" in -h|--help) printf 'Usage: sh system-check.sh\nRead-only OS, CPU/load, memory, disk and failed-service summary.\n'; exit 0;; esac
[ "$#" = 0 ] || { printf 'This tool takes no arguments.\n' >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
printf '=== Operating system ===\n'
uname -srm
if [ -r /etc/os-release ]; then sed -n '/^PRETTY_NAME=/p' /etc/os-release; elif [ -r /etc/openwrt_release ]; then sed -n '/^DISTRIB_DESCRIPTION=/p' /etc/openwrt_release; fi
printf '\n=== CPU and load ===\n'
uptime
if [ -r /proc/cpuinfo ]; then awk '/^processor[[:space:]]*:/ {n++} END {if(n) print "CPU logical cores: " n}' /proc/cpuinfo; fi
printf '\n=== Memory (kB) ===\n'
if [ -r /proc/meminfo ]; then awk '/^(MemTotal|MemAvailable|MemFree|SwapTotal|SwapFree):/ {print}' /proc/meminfo; fi
printf '\n=== Filesystem space ===\n'
df -h
printf '\n=== Largest processes by memory ===\n'
if ps -eo pid,comm,pcpu,pmem --sort=-pmem >/dev/null 2>&1; then
    ps -eo pid,comm,pcpu,pmem --sort=-pmem | head -n 11
else printf 'This ps version does not provide a sortable memory view.\n'
fi
printf '\n=== Failed services ===\n'
if have systemctl && systemctl list-units --failed --no-pager >/dev/null 2>&1; then
    systemctl list-units --failed --no-pager
else printf 'systemd service status is unavailable on this system.\n'
fi
