#!/bin/sh
# Configure dnsmasq's upstream DNS on OpenWrt. Requires root; BusyBox compatible.
set -eu

SECTION='dhcp.@dnsmasq[0]'
BACKUP='/etc/system-toolbox/dns'
LOCK='/tmp/system-toolbox-dns.lock'

usage() {
    cat <<'EOF'
OpenWrt DNS helper
  sh dns.sh                         Choose DNS interactively
  sh dns.sh 1.1.1.1 8.8.8.8          Set custom DNS servers
  sh dns.sh 127.0.0.1#5453            Set a resolver with a custom port
  sh dns.sh --show                   Show current upstream DNS
  sh dns.sh --restore                Restore the previous DNS settings
Supports literal IPv4/IPv6 addresses, optionally followed by #port.
DoH URLs require a separate DoH client; do not enter https:// URLs here.
EOF
}

fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
show() {
    printf 'Ignore upstream resolv file: %s\n' "$(uci -q get "$SECTION.noresolv" || printf '0')"
    printf 'DNS forwarders: %s\n' "$(uci -q get "$SECTION.server" || printf '(from upstream resolv file)')"
}

case "${1:-}" in -h|--help) usage; exit 0;; esac
[ "$(id -u)" = 0 ] || fail 'Run this on your OpenWrt router as root.'
command -v uci >/dev/null 2>&1 || fail 'This helper requires OpenWrt with UCI.'
[ -x /etc/init.d/dnsmasq ] || fail 'dnsmasq is not installed.'
[ "$(uci -q get "$SECTION" || true)" = dnsmasq ] || fail 'The first dnsmasq instance was not found.'

if [ "$#" = 0 ]; then
    show
    printf '\n1) Cloudflare  2) Google  3) Quad9  4) Custom  5) Restore\nChoice [1]: '
    IFS= read -r choice || fail 'Pass DNS addresses as arguments when stdin is not interactive.'
    case "$choice" in
        ''|1) set -- 1.1.1.1 1.0.0.1;;
        2) set -- 8.8.8.8 8.8.4.4;;
        3) set -- 9.9.9.9 149.112.112.112;;
        4)
            printf 'DNS IP addresses, separated by spaces: '
            IFS= read -r addresses || fail 'No DNS addresses supplied.'
            set -f
            set -- $addresses
            [ "$#" -gt 0 ] || fail 'No DNS addresses supplied.'
            ;;
        5) set -- --restore;;
        *) fail 'Unknown choice.';;
    esac
fi
case "$1" in
    --show) [ "$#" = 1 ] || fail 'Use --show alone.'; show; exit 0;;
    --restore) [ "$#" = 1 ] || fail 'Use --restore alone.';;
    -*) fail 'Unknown option. Use --help.';;
    *)
        for server in "$@"; do
            case "$server" in ''|*[!0-9a-fA-F.:\#]*) fail "Use a DNS IP address, optionally with #port: $server";; esac
            # Let dnsmasq itself validate IPv4, IPv6 and optional port syntax.
            dnsmasq --test --conf-file=/dev/null "--server=$server" >/dev/null 2>&1 || fail "Invalid DNS server: $server"
        done
        ;;
esac
[ -z "$(uci changes dhcp)" ] || fail 'Save or revert pending DHCP/DNS changes in LuCI before running this helper.'
mkdir "$LOCK" 2>/dev/null || fail 'Another DNS helper is running.'
trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Save the complete file privately, but restore only the two DNS options.
restore_dns() {
    uci revert dhcp || return 1
    old_noresolv=$(uci -c "$BACKUP" -q get "$SECTION.noresolv" || true)
    old_servers=$(uci -c "$BACKUP" -q get "$SECTION.server" || true)
    uci -q delete "$SECTION.noresolv" || true
    uci -q delete "$SECTION.server" || true
    if [ -n "$old_noresolv" ]; then uci set "$SECTION.noresolv=$old_noresolv" || return 1; fi
    set -f
    for server in $old_servers; do uci add_list "$SECTION.server=$server" || return 1; done
    uci commit dhcp || return 1
    /etc/init.d/dnsmasq restart
}

if [ "$1" = --restore ]; then
    [ -f "$BACKUP/dhcp" ] || fail 'No previous DNS backup exists.'
    restore_dns
    printf 'Previous DNS settings restored.\n'
    show
    exit 0
fi

umask 077
mkdir -p "$BACKUP"
cp /etc/config/dhcp "$BACKUP/dhcp"
chmod 600 "$BACKUP/dhcp"
rollback() {
    trap - INT TERM
    printf 'DNS change did not complete; restoring previous settings.\n' >&2
    restore_dns || printf 'Automatic restore failed. Backup: %s/dhcp\n' "$BACKUP" >&2
}
trap 'rollback; exit 130' INT
trap 'rollback; exit 143' TERM
if ! (
    uci set "$SECTION.noresolv=1" || exit 1
    uci -q delete "$SECTION.server" || true
    for server in "$@"; do uci add_list "$SECTION.server=$server" || exit 1; done
    uci commit dhcp || exit 1
    /etc/init.d/dnsmasq restart
); then
    rollback
    exit 1
fi

# Test the router's actual resolver, rather than just checking a saved setting.
if ! nslookup -type=A example.org 127.0.0.1 >/dev/null 2>&1; then
    rollback
    fail 'The new DNS did not answer through dnsmasq. Previous DNS restored.'
fi
trap 'exit 130' INT
trap 'exit 143' TERM
printf 'DNS updated and tested successfully.\n'
show
