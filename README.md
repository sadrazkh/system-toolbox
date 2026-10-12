# System Toolbox

Small, practical scripts for OpenWrt and Linux system maintenance. More tools, including Ubuntu helpers, can be added here over time.

## OpenWrt DNS helper

Run this **in the router's SSH terminal as root**, not in Windows PowerShell or on Ubuntu. It configures the first dnsmasq instance in `/etc/config/dhcp`.

### One command: choose your DNS

```sh
wget -qO /tmp/system-toolbox-dns.sh https://raw.githubusercontent.com/sadrazkh/system-toolbox/main/openwrt/dns.sh && sh /tmp/system-toolbox-dns.sh
```

Choose Cloudflare, Google, Quad9, custom DNS, or restore the previous settings.

### One command: use custom servers

Replace the two addresses at the end with your preferred DNS servers:

```sh
wget -qO /tmp/system-toolbox-dns.sh https://raw.githubusercontent.com/sadrazkh/system-toolbox/main/openwrt/dns.sh && sh /tmp/system-toolbox-dns.sh 1.1.1.1 8.8.8.8
```

After downloading, you can run the same file again:

```sh
sh /tmp/system-toolbox-dns.sh 9.9.9.9 149.112.112.112
sh /tmp/system-toolbox-dns.sh --show
sh /tmp/system-toolbox-dns.sh --restore
```

Literal IPv4/IPv6 addresses and `IP#port` are supported. DoH URLs such as `https://…/dns-query` require a separate DoH client and are not valid dnsmasq forwarders.

The helper sets `noresolv=1` and replaces the DNS `server` list. It saves the previous configuration privately in `/etc/system-toolbox/dns/dhcp`, restarts dnsmasq, then checks a real lookup through `127.0.0.1`. If the lookup fails, it restores the previous DNS settings. Restore changes only `server` and `noresolv`; other DHCP settings remain intact. Save any pending LuCI DHCP/DNS edits first. Each successful apply replaces the previous backup.

VPN routing and DNS interception rules still control where these requests travel. This changes OpenWrt's dnsmasq upstreams, not the VPN application's own DoH settings. dnsmasq briefly restarts; the VPN service is not restarted.

[راهنمای فارسی](README.fa.md) · [OpenWrt DHCP/DNS documentation](https://openwrt.org/docs/guide-user/base-system/dhcp_configuration)
