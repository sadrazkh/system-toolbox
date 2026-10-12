#!/bin/sh
# Read-only connectivity checks; works with common Linux tools and BusyBox.
set -u
LC_ALL=C
export LC_ALL
have() { command -v "$1" >/dev/null 2>&1; }
case "${1:-}" in -h|--help) printf 'Usage: sh network-check.sh [hostname]\nDefault: example.org. Read-only route, DNS and HTTPS checks.\n'; exit 0;; esac
[ "$#" -le 1 ] || { printf 'Supply one hostname, without a URL.\n' >&2; exit 1; }
target=${1:-example.org}
case "$target" in ''|-*|*[!a-zA-Z0-9.-]*) printf 'Invalid hostname.\n' >&2; exit 1;; esac
printf 'Network diagnostics for %s\n' "$target"
printf '\n=== Default routes ===\n'
if have ip; then ip -4 route show default; ip -6 route show default; else printf 'ip command is unavailable.\n'; fi
printf '\n=== Configured system resolvers ===\n'
if [ -r /etc/resolv.conf ]; then cat /etc/resolv.conf; fi
printf '\n=== IP connectivity ===\n'
if have ping; then
    ping -c 2 -W 3 1.1.1.1 || printf 'ICMP did not respond; some networks block ping.\n'
else printf 'ping is unavailable.\n'
fi
failed=0
printf '\n=== DNS lookup ===\n'
if have nslookup; then
    if have timeout; then timeout 15 nslookup "$target" || failed=$((failed+1)); else nslookup "$target" || failed=$((failed+1)); fi
elif have getent; then
    if have timeout; then timeout 15 getent hosts "$target" || failed=$((failed+1)); else getent hosts "$target" || failed=$((failed+1)); fi
else printf 'No DNS lookup tool installed.\n'; failed=$((failed+1))
fi
printf '\n=== HTTPS connectivity ===\n'
if have curl; then
    curl -fLsS --connect-timeout 5 --max-time 15 -o /dev/null -w 'HTTP status: %{http_code}; remote IP: %{remote_ip}; time: %{time_total}s\n' "https://$target/" || failed=$((failed+1))
elif have wget; then
    if wget -q -T 15 -O /dev/null "https://$target/"; then printf 'HTTPS request succeeded.\n'; else printf 'HTTPS request failed.\n'; failed=$((failed+1)); fi
else printf 'Neither curl nor wget is installed.\n'; failed=$((failed+1))
fi
printf '\nDNS/HTTPS checks that failed or could not run: %s\n' "$failed"
[ "$failed" = 0 ]
