#!/bin/sh
# Read-only listening sockets. Run as root to see all process owners.
set -u
case "${1:-}" in -h|--help) printf 'Usage: sh ports.sh\nLists listening TCP/UDP sockets. Root can see more process owners.\n'; exit 0;; esac
[ "$#" = 0 ] || { printf 'This tool takes no arguments.\n' >&2; exit 1; }
printf 'Listening TCP/UDP sockets (no firewall rules are changed)\n'
if command -v ss >/dev/null 2>&1; then ss -lntup
elif command -v netstat >/dev/null 2>&1; then netstat -lntup
else printf 'Install iproute2 (ss) or net-tools (netstat) to use this tool.\n' >&2; exit 1
fi
