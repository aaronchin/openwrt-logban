# openwrt-logban

`openwrt-logban` is a lightweight OpenWrt service that watches authentication logs in real time and blocks abusive source IPs after repeated failed login attempts within a configurable time window.

It is designed for resource-constrained OpenWrt targets:

- BusyBox `ash` compatible
- Works with `logread -f` or a plain log file
- Supports `dropbear` and `uhttpd/LuCI` failure patterns
- Supports IPv4 and IPv6
- Supports whitelist IPs and CIDR ranges
- Persists bans into `fw4` nftables snippets and restores them across firewall reloads/reboots
- Uses `fw4`/`nftables` primarily and falls back to `iptables`
- Supports automatic unban after `ban_time`

## Layout

- `files/usr/sbin/logban.sh`: main monitor script
- `files/etc/init.d/logban`: procd service wrapper
- `files/etc/config/logban`: UCI config
- `package/logban`: OpenWrt package skeleton for building an `ipk`

## Raw Deployment

Copy the files to an OpenWrt device:

```sh
scp files/usr/sbin/logban.sh root@router:/usr/sbin/logban.sh
scp files/etc/init.d/logban root@router:/etc/init.d/logban
scp files/etc/config/logban root@router:/etc/config/logban
ssh root@router 'chmod +x /usr/sbin/logban.sh /etc/init.d/logban && /etc/init.d/logban enable && /etc/init.d/logban start'
```

## Notes

- Default patterns target common `dropbear` and `uhttpd/LuCI` failure lines. Adjust `/etc/config/logban` for your actual log format.
- Whitelists can be individual IPs or CIDR ranges via `ignore_ip` and `ignore_net`.
- When `firewall_backend` is `auto`, the service prefers `fw4`, then `nft`, then `iptables`.
- For current OpenWrt releases, `logread -f` is usually more reliable than watching `/var/log/auth.log` directly.
- Runtime state is stored under `/var/run/logban`.
- Persistent ban lists are stored under `/etc/logban`, and `fw4` snippets are written under `/usr/share/nftables.d/`.

## Build As OpenWrt Package

OpenWrt builds `.ipk` packages, not Android-style `.apk` packages.

Copy `package/logban` into your OpenWrt source tree or SDK, then build:

```sh
make package/logban/compile V=s
```

The generated package will be under `bin/packages/*/*/`.
