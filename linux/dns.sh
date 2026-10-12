#!/bin/sh
# DNS settings through the active Linux network manager. POSIX shell.
set -eu
set -f
LC_ALL=C
export LC_ALL
STATE='/var/lib/system-toolbox/dns'
RESOLV='/etc/resolv.conf'
backend=auto
iface=''
action=apply

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
active() { have systemctl && systemctl is-active --quiet "$1"; }
usage() {
    cat <<'EOF'
Linux DNS helper (run with sudo or as root)
  sh dns.sh [--interface eth0] 1.1.1.1 8.8.8.8
  sh dns.sh                         Interactive DNS selection
  sh dns.sh --show                  Show detected manager and DNS
  sh dns.sh --restore               Restore the last successful change
  sh dns.sh --backend NAME ...      Select a manager explicitly
Managers: auto, nm, networkd, resolved, resolvconf, file.
IPv4 and IPv6 literals are supported. DoH URLs and custom ports are not.
NetworkManager changes the selected active uplink profile, not VPN profiles.
EOF
}
while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0;;
        --backend) [ "$#" -ge 2 ] || die 'Missing backend.'; backend=$2; shift 2;;
        --interface) [ "$#" -ge 2 ] || die 'Missing interface.'; iface=$2; shift 2;;
        --show|--restore) action=${1#--}; shift;;
        --) shift; break;;
        -*) die "Unknown option: $1";;
        *) break;;
    esac
done
[ "$action" = apply ] || [ "$#" = 0 ] || die 'Do not supply DNS addresses with --show/--restore.'
case "$iface" in *[!a-zA-Z0-9_.:-]*) die 'Invalid interface name.';; esac
[ "$(id -u)" = 0 ] || die 'Run with sudo or as root.'

if [ "$action" = restore ]; then
    [ -f "$STATE/last" ] || die 'No previous DNS backup exists.'
    name=$(cat "$STATE/last")
    case "$name" in backup.*) ;; *) die 'Invalid backup record.';; esac
    case "$name" in */*) die 'Invalid backup record.';; esac
    snapshot="$STATE/$name"
    [ -d "$snapshot" ] || die 'The recorded backup is missing.'
    backend=$(cat "$snapshot/backend")
else
    if [ "$backend" = auto ]; then
        if have nmcli && nmcli general status >/dev/null 2>&1; then backend=nm
        elif active systemd-networkd && active systemd-resolved; then backend=networkd
        elif active systemd-resolved; then backend=resolved
        elif have resolvconf && { [ -d /etc/resolvconf/resolv.conf.d ] || [ -f /etc/resolvconf.conf ]; }; then backend=resolvconf
        else backend=file
        fi
    fi
fi
case "$backend" in nm|networkd|resolved|resolvconf|file) ;; *) die "Unsupported backend: $backend";; esac

default_interface() {
    have ip || return 1
    default_routes=$(ip -4 route show default) || return 1
    [ -n "$default_routes" ] || default_routes=$(ip -6 route show default) || return 1
    printf '%s\n' "$default_routes" | awk '{for(i=1;i<=NF;i++)if($i=="dev"){print $(i+1);exit}}'
}
nm_select() {
    nm_requested_iface=$iface
    profiles=$(nmcli -t -e no -f UUID,DEVICE,TYPE connection show --active) || return 1
    eligible=$(printf '%s\n' "$profiles" | awk -F: '$2!="" && $2!="--" && $3!="vpn" && $3!="wireguard" && $3!="tun" && $3!="ip-tunnel" && $2!="lo" {print $1 ":" $2}')
    [ -n "$iface" ] || iface=$(default_interface || true)
    selected=$(printf '%s\n' "$eligible" | awk -F: -v d="$iface" '$2==d {print;exit}')
    if [ -z "$selected" ]; then
        [ -z "$nm_requested_iface" ] || die 'The selected interface has no eligible active NetworkManager uplink profile. Use --interface.'
        [ "$(printf '%s\n' "$eligible" | awk 'NF {n++} END {print n+0}')" = 1 ] || die 'Choose the active uplink with --interface; multiple or no profiles found.'
        selected=$eligible
    fi
    uuid=${selected%%:*}; iface=${selected#*:}
}

if [ "$action" != restore ]; then
    case "$backend" in
        nm) have nmcli || die 'nmcli is missing.'; nm_select || die 'Cannot select a NetworkManager connection.';;
        networkd)
            active systemd-networkd && active systemd-resolved || die 'networkd and resolved must both be active.'
            [ -n "$iface" ] || iface=$(default_interface || true)
            [ -n "$iface" ] || die 'Specify --interface.'
            have networkctl && have resolvectl || die 'networkctl/resolvectl is missing.'
            network_file=$(networkctl status "$iface" --no-pager | sed -n 's/^[[:space:]]*Network File:[[:space:]]*//p')
            case "$network_file" in /etc/systemd/network/*.network|/run/systemd/network/*.network|/usr/lib/systemd/network/*.network|/lib/systemd/network/*.network) ;; *) die 'Cannot find the .network file for this interface.';; esac
            target="/etc/systemd/network/$(basename "$network_file").d/99-system-toolbox-dns.conf"
            ;;
        resolved)
            active systemd-resolved && have resolvectl || die 'systemd-resolved is not active.'
            target='/etc/systemd/resolved.conf.d/99-system-toolbox-dns.conf'
            ;;
        resolvconf)
            have resolvconf || die 'resolvconf is missing.'
            if [ -d /etc/resolvconf/resolv.conf.d ]; then
                subtype=debian; target='/etc/resolvconf/resolv.conf.d/head'
            elif [ -f /etc/resolvconf.conf ]; then
                subtype=openresolv; target='/etc/resolvconf.conf'
            else die 'Unrecognized resolvconf configuration layout.'
            fi
            ;;
        file)
            [ -f "$RESOLV" ] && [ ! -L "$RESOLV" ] || die 'resolv.conf is missing or is a managed symlink. Use its network manager.'
            if grep -Eiq 'generated|NetworkManager|resolvconf|dhcpcd|systemd|WSL' "$RESOLV"; then die 'resolv.conf is managed; refusing to overwrite it. Select/configure its manager.'; fi
            if have pgrep && { pgrep -x dhclient >/dev/null || pgrep -x dhcpcd >/dev/null; }; then die 'A DHCP client owns DNS; configure its manager instead of overwriting resolv.conf.'; fi
            target=$RESOLV
            ;;
    esac
    if [ "$backend" = resolved ] || [ "$backend" = networkd ]; then
        case "$(readlink -f "$RESOLV" || true)" in /run/systemd/resolve/stub-resolv.conf|/run/systemd/resolve/resolv.conf) ;; *) die 'resolv.conf does not use systemd-resolved; configure that integration first.';; esac
    fi
    [ "$backend" = nm ] || [ ! -L "$target" ] || die 'Refusing to replace a symlinked configuration file.'
fi

show() {
    printf 'DNS manager: %s\n' "$backend"
    case "$backend" in
        nm)
            printf 'Interface: %s\n' "$iface"
            nmcli -g ipv4.dns,ipv6.dns,ipv4.ignore-auto-dns,ipv6.ignore-auto-dns connection show uuid "$uuid"
            ;;
        networkd|resolved) resolvectl status;;
        *) cat "$RESOLV";;
    esac
}
[ "$action" != show ] || { show; exit 0; }
if [ "$action" = apply ] && [ "$#" = 0 ]; then
    show
    printf '\n1) Cloudflare  2) Google  3) Quad9  4) Custom\nChoice [1]: '
    IFS= read -r choice || die 'Pass DNS IP addresses when stdin is not interactive.'
    case "$choice" in
        ''|1) set -- 1.1.1.1 1.0.0.1;;
        2) set -- 8.8.8.8 8.8.4.4;;
        3) set -- 9.9.9.9 149.112.112.112;;
        4) printf 'DNS IP addresses separated by spaces: '; IFS= read -r addresses || die 'No DNS supplied.'; set -- $addresses;;
        *) die 'Unknown choice.';;
    esac
fi

valid_ip() {
    awk -v ip="$1" 'function v4(s,a,n,i){n=split(s,a,".");if(n!=4)return 0;for(i=1;i<=4;i++)if(a[i]!~/^[0-9]+$/||a[i]>255||length(a[i])>3||(length(a[i])>1&&substr(a[i],1,1)=="0"))return 0;return 1}
    BEGIN {if(index(ip,":")==0)exit !v4(ip);if(ip!~/^[0-9a-fA-F:.]+$/||index(ip,":::")>0)exit 1;compressed=index(ip,"::")>0;x=ip;if(compressed){sub(/::/,":Z:",x);if(index(x,"::")>0)exit 1}else if(ip~/^:|:$/)exit 1;n=split(x,a,":");count=0;for(i=1;i<=n;i++){if(a[i]==""||a[i]=="Z")continue;if(index(a[i],".")){if(i!=n||!v4(a[i]))exit 1;count+=2}else{if(a[i]!~/^[0-9a-fA-F]+$/||length(a[i])>4)exit 1;count++}}if(compressed)exit !(count<8);exit !(count==8)}'
}
if [ "$action" = apply ]; then
    [ "$#" -gt 0 ] || die 'No DNS addresses supplied.'
    for server in "$@"; do valid_ip "$server" || die "Invalid DNS IP: $server"; done
    if [ "$backend" = file ] || [ "$backend" = resolvconf ]; then [ "$#" -le 3 ] || die 'These resolv.conf backends support at most three servers.'; fi
fi
if [ "$action" = apply ] && ! have getent && ! have nslookup; then die 'Install getent or nslookup before changing DNS.'; fi

umask 077
mkdir -p "$STATE"
chmod 700 "$STATE"
mkdir "$STATE/lock" 2>/dev/null || die 'Another DNS helper is running.'
cleanup() { rmdir "$STATE/lock" 2>/dev/null || true; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

save_file() {
    printf '%s\n' "$target" > "$snapshot/target"
    if [ -e "$target" ]; then cp -p "$target" "$snapshot/file"; printf 'yes\n' > "$snapshot/existed"; else printf 'no\n' > "$snapshot/existed"; fi
}
restore_file() {
    restore_target=$(cat "$snapshot/target")
    if [ "$(cat "$snapshot/existed")" = yes ]; then
        cp -p "$snapshot/file" "$restore_target" || return 1
    else rm -f "$restore_target" || return 1
    fi
}
link_value() {
    link_output=$(resolvectl "$1" "$iface") || return 1
    printf '%s\n' "$link_output" | sed 's/^[^:]*:[[:space:]]*//'
}
restore_link() {
    link_setting=$1
    link_original=$2
    if [ -z "$link_original" ]; then resolvectl "$link_setting" "$restore_iface" ''
    else set -- $link_original; resolvectl "$link_setting" "$restore_iface" "$@"
    fi
}
restore() {
    case "$(cat "$snapshot/backend")" in
        nm)
            restore_uuid=$(cat "$snapshot/uuid"); restore_iface=$(cat "$snapshot/interface")
            nmcli connection modify uuid "$restore_uuid" \
                ipv4.dns "$(cat "$snapshot/ipv4.dns")" ipv6.dns "$(cat "$snapshot/ipv6.dns")" \
                ipv4.ignore-auto-dns "$(cat "$snapshot/ipv4.ignore-auto-dns")" ipv6.ignore-auto-dns "$(cat "$snapshot/ipv6.ignore-auto-dns")" || return 1
            nmcli device reapply "$restore_iface"
            ;;
        networkd)
            restore_file || return 1
            networkctl reload || return 1
            restore_iface=$(cat "$snapshot/interface")
            restore_link dns "$(cat "$snapshot/link.dns")" || return 1
            restore_link domain "$(cat "$snapshot/link.domains")" || return 1
            resolvectl default-route "$restore_iface" "$(cat "$snapshot/link.default-route")"
            ;;
        resolved) restore_file && systemctl restart systemd-resolved;;
        resolvconf) restore_file && resolvconf -u;;
        file) restore_file;;
        *) return 1;;
    esac
}
if [ "$action" = restore ]; then
    restore || die 'Restore failed; backup was preserved.'
    printf 'Previous DNS settings restored from %s\n' "$snapshot"
    exit 0
fi

snapshot=$(mktemp -d "$STATE/backup.XXXXXX")
printf '%s\n' "$backend" > "$snapshot/backend"
case "$backend" in
    nm)
        printf '%s\n' "$uuid" > "$snapshot/uuid"
        printf '%s\n' "$iface" > "$snapshot/interface"
        for property in ipv4.dns ipv6.dns ipv4.ignore-auto-dns ipv6.ignore-auto-dns; do
            nmcli -g "$property" connection show uuid "$uuid" > "$snapshot/$property" || die 'Cannot read the original profile DNS.'
        done
        ;;
    networkd)
        save_file
        printf '%s\n' "$iface" > "$snapshot/interface"
        link_value dns > "$snapshot/link.dns" || die 'Cannot read current link DNS.'
        link_value domain > "$snapshot/link.domains" || die 'Cannot read current link DNS domains.'
        link_value default-route > "$snapshot/link.default-route" || die 'Cannot read the link DNS default-route setting.'
        ;;
    *) save_file;;
esac
rollback() {
    trap - INT TERM
    printf 'DNS change failed; restoring previous settings.\n' >&2
    if restore; then printf 'Previous DNS settings restored.\n' >&2; else printf 'Restore failed. Backup: %s\n' "$snapshot" >&2; fi
}
trap 'rollback; exit 130' INT
trap 'rollback; exit 143' TERM

apply() {
    case "$backend" in
        nm)
            v4=''; v6=''
            for server in "$@"; do case "$server" in *:*) v6="$v6 $server";; *) v4="$v4 $server";; esac; done
            nmcli connection modify uuid "$uuid" ipv4.dns "${v4# }" ipv6.dns "${v6# }" ipv4.ignore-auto-dns yes ipv6.ignore-auto-dns yes || return 1
            nmcli device reapply "$iface"
            ;;
        networkd)
            mkdir -p "$(dirname "$target")" || return 1
            { printf '[Network]\nDNS=\nDNS=%s\nDomains=~.\nDNSDefaultRoute=yes\n[DHCPv4]\nUseDNS=no\n[DHCPv6]\nUseDNS=no\n[IPv6AcceptRA]\nUseDNS=no\n' "$*"; } > "$target" || return 1
            networkctl reload || return 1
            resolvectl dns "$iface" "$@" || return 1
            resolvectl domain "$iface" $(cat "$snapshot/link.domains") '~.' || return 1
            resolvectl default-route "$iface" yes
            ;;
        resolved)
            mkdir -p "$(dirname "$target")" || return 1
            printf '[Resolve]\nDNS=\nDNS=%s\nFallbackDNS=\nDomains=~.\n' "$*" > "$target" || return 1
            systemctl restart systemd-resolved
            ;;
        resolvconf)
            if [ "$subtype" = debian ]; then
                { for server in "$@"; do printf 'nameserver %s\n' "$server"; done
                  if [ -f "$snapshot/file" ]; then awk '$1!="nameserver"' "$snapshot/file"; fi
                } > "$target" || return 1
            else
                { awk '/^# BEGIN system-toolbox DNS$/{skip=1;next}/^# END system-toolbox DNS$/{skip=0;next}!skip{print}' "$snapshot/file"
                  printf "# BEGIN system-toolbox DNS\nname_servers='%s'\n# END system-toolbox DNS\n" "$*"
                } > "$target" || return 1
            fi
            resolvconf -u
            ;;
        file)
            { for server in "$@"; do printf 'nameserver %s\n' "$server"; done
              awk '$1!="nameserver"' "$snapshot/file"
            } > "$target"
            ;;
    esac
}
check_dns() {
    if have getent; then
        if have timeout; then timeout 20 getent hosts example.org >/dev/null 2>&1; else getent hosts example.org >/dev/null 2>&1; fi
    else
        if have timeout; then timeout 20 nslookup example.org >/dev/null 2>&1; else nslookup example.org >/dev/null 2>&1; fi
    fi
}
if ! apply "$@"; then rollback; die 'DNS settings could not be applied.'; fi
if ! check_dns; then rollback; die 'System DNS lookup failed after the change.'; fi
printf '%s\n' "${snapshot##*/}" > "$STATE/last.new"
mv "$STATE/last.new" "$STATE/last"
trap 'exit 130' INT
trap 'exit 143' TERM
printf 'DNS updated and system lookup passed. Manager: %s\nBackup: %s\n' "$backend" "$snapshot"
