# System Toolbox

Practical OpenWrt and Linux tools for DNS, networking and system health.

## One-command menu

Run this in a Linux terminal or an OpenWrt SSH session:

```sh
wget -qO /tmp/system-toolbox.sh https://raw.githubusercontent.com/sadrazkh/system-toolbox/main/toolbox.sh && sh /tmp/system-toolbox.sh
```

If wget is unavailable, use curl:

```sh
curl -fLsS -o /tmp/system-toolbox.sh https://raw.githubusercontent.com/sadrazkh/system-toolbox/main/toolbox.sh && sh /tmp/system-toolbox.sh
```

| Tool | What it does |
| --- | --- |
| DNS settings | Detects the network manager, sets custom resolvers, saves a private backup and rolls back a failed lookup |
| Network diagnostics | Shows default routes/resolvers, tests DNS, IP connectivity and HTTPS |
| System health | Shows CPU/load, RAM, disk space, largest processes and failed systemd services |
| Listening ports | Lists listening TCP/UDP sockets using ss or netstat |

Only the DNS tool changes settings. The diagnostics do not install packages, alter firewall rules or upload reports. The launcher downloads only the selected tool. DNS asks for sudo when needed; on OpenWrt, run as root.

## DNS: one command with your own servers

**Ubuntu/Debian/Fedora/Arch/openSUSE and other Linux systems with a supported manager:**

```sh
wget -qO /tmp/system-toolbox-dns.sh https://raw.githubusercontent.com/sadrazkh/system-toolbox/main/dns.sh && sudo sh /tmp/system-toolbox-dns.sh 1.1.1.1 8.8.8.8
```

**OpenWrt, or a Linux terminal already running as root:**

```sh
wget -qO /tmp/system-toolbox-dns.sh https://raw.githubusercontent.com/sadrazkh/system-toolbox/main/dns.sh && sh /tmp/system-toolbox-dns.sh 1.1.1.1 8.8.8.8
```

Replace the last two IPs. Omit them for interactive selection. After downloading, these commands also work offline (add sudo on Linux when necessary):

```sh
sh /tmp/system-toolbox-dns.sh --show
sh /tmp/system-toolbox-dns.sh --restore
sh /tmp/system-toolbox-dns.sh --interface eth0 9.9.9.9 149.112.112.112
```

`--interface` applies to Linux NetworkManager/networkd. With multiple active uplinks, choose one explicitly. The launcher uses fresh downloads, so keep this DNS file or a checkout for offline restore. `/tmp` files disappear after a reboot.

### Supported configurations

The active manager matters more than the distribution name. Detection order:

| Manager | Change and persistence |
| --- | --- |
| OpenWrt dnsmasq/UCI | Updates the first dnsmasq instance's server/noresolv options; restarts dnsmasq |
| NetworkManager | Updates DNS and ignore-auto-dns in the selected active uplink profile, then reapplies it without connection down/up |
| systemd-networkd + resolved | Adds a DNS-only .network drop-in, disables DHCP/RA DNS for that link, reloads networkd and applies resolver settings |
| Standalone systemd-resolved | Adds a persistent global resolved.conf drop-in with a default DNS route and restarts only resolved |
| Debian resolvconf | Prepends custom nameservers to its persistent head file and regenerates resolv.conf |
| openresolv | Adds a tagged name_servers setting to resolvconf.conf and regenerates resolv.conf |
| Unmanaged regular resolv.conf | Replaces nameserver lines while preserving search/options |

The resolvconf backends prioritize custom servers; they do not remove DHCP/VPN records. DHCP clients, VPN DNS routing and other connections can still affect resolution. Specific VPN DNS routes are preserved. The helper refuses unfamiliar managed files/symlinks, generated WSL/container resolver files and ambiguous uplinks instead of overwriting them. This is not a claim of support for every possible distribution/network configuration.

Linux supports IPv4/IPv6 literals. OpenWrt additionally supports `IP#port`. DoH URLs need a separate DoH client. Changing system DNS does not change a VPN application's own DoH configuration.

Linux backups are private snapshots in `/var/lib/system-toolbox/dns`; restore uses the snapshot before the most recent successful apply. OpenWrt saves its previous configuration in `/etc/system-toolbox/dns/dhcp` and restores only its two DNS options. Both helpers check a real system lookup and attempt rollback on apply/lookup failure. NetworkManager does not select VPN/WireGuard profiles automatically. Services may briefly pause DNS during reload/restart; the helper does not restart a VPN service.

## Run individual tools

After downloading the menu:

```sh
sh /tmp/system-toolbox.sh network wikipedia.org
sh /tmp/system-toolbox.sh system
sh /tmp/system-toolbox.sh ports
sh /tmp/system-toolbox.sh dns --show
```

From a trusted checkout, `sh toolbox.sh --local system` uses local files without downloading. Diagnostics display local network/process information; review it before sharing it.

## Development and validation

Edit `linux/dns.sh` or `openwrt/dns.sh`, then run `python3 tools/build-dns.py` to regenerate the self-contained `dns.sh`. Run `python3 -m unittest discover -s tests -v` for isolated fixtures covering manager selection, IPv6, persistence, restore and failed-change rollback. Fixtures never change the host's networking.

GitHub Actions runs those fixtures and read-only smoke checks on Ubuntu 22.04/24.04. Manager commands in the fixture tests are simulated; they are not full live NetworkManager/networkd integration tests. The OpenWrt helper, shared entry point and diagnostics have also been checked on a Xiaomi AX3200 running OpenWrt 24.10.8. Actual testing on every listed distribution is not implied.

[راهنمای فارسی](README.fa.md)

Manager references: [OpenWrt DHCP/DNS](https://openwrt.org/docs/guide-user/base-system/dhcp_configuration), [NetworkManager settings](https://networkmanager.pages.freedesktop.org/NetworkManager/NetworkManager/nm-settings-nmcli.html), [systemd resolver configuration](https://github.com/systemd/systemd/blob/main/man/resolved.conf.xml), [resolvconf](https://manpages.debian.org/unstable/resolvconf/resolvconf.8.en.html), [openresolv](https://manpages.debian.org/unstable/openresolv/resolvconf.conf.5.en.html).
