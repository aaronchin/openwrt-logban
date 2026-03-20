# openwrt-logban

English | [中文](#中文說明)

`openwrt-logban` is a lightweight OpenWrt service for real-time detection of failed authentication attempts and automatic source IP blocking.

It is intended as a small, practical alternative to `fail2ban` for OpenWrt targets with limited CPU, RAM, and storage.

## Features

- BusyBox `ash` compatible
- Watches `logread -f` in real time, or a plain log file
- Matches common `dropbear` and `uhttpd/LuCI` login failure logs
- Supports both IPv4 and IPv6
- Supports whitelist IPs and CIDR ranges
- Uses `fw4` first, then `nftables`, then `iptables`
- Supports temporary bans with automatic unban
- Persists ban lists across `fw4 reload` and reboot when using `fw4`
- Includes an OpenWrt package skeleton for building an `.ipk`

## Repository Layout

- `files/usr/sbin/logban.sh`
  Main monitor script
- `files/etc/init.d/logban`
  `procd` service wrapper
- `files/etc/config/logban`
  UCI configuration
- `package/logban`
  OpenWrt package skeleton for SDK/source-tree builds

## How It Works

`logban.sh` reads authentication logs line by line. When a line matches one of the configured failure patterns, it extracts the source IP, checks whether the IP is whitelisted, then records the failure timestamp.

If the same source exceeds `max_retry` failures within `find_time` seconds, the IP is banned for `ban_time` seconds.

Firewall behavior:

- `fw4` mode
  Runtime bans are applied immediately with `nft`
- `fw4` mode
  Persistent ban lists are stored in `/etc/logban/banlist4` and `/etc/logban/banlist6`
- `fw4` mode
  Persistent nft snippets are generated under `/usr/share/nftables.d/`
- `nft` mode
  Uses a dedicated nftables table and sets
- `iptables` mode
  Falls back to `iptables` and `ip6tables` chains when available

## Default Detection Patterns

The default config includes patterns for common OpenWrt authentication failures:

- `Bad password attempt for`
- `Failed password for`
- `Login attempt for nonexistent user`
- `Exit before auth from <`
- `luci: failed login`
- `luci: invalid password`
- `authentication failure`

These are intended to cover typical `dropbear` and `uhttpd/LuCI` failure messages. You should still verify them against your device logs.

## Default Whitelist

The default config includes:

- `127.0.0.1`
- `::1`
- `192.168.0.0/16`
- `10.0.0.0/8`
- `172.16.0.0/12`
- `fc00::/7`
- `fe80::/10`

Adjust these to match your environment. If your router is exposed behind unusual addressing or reverse proxies, do not rely on defaults blindly.

## Configuration

UCI config file:

- `/etc/config/logban`

Current supported options:

- `enabled`
  `1` to enable the service, `0` to disable
- `backend`
  `logread` or `file`
- `log_file`
  Used only when `backend='file'`
- `firewall_backend`
  `auto`, `fw4`, `nft`, or `iptables`
- `find_time`
  Sliding detection window in seconds
- `max_retry`
  Number of failures before ban
- `ban_time`
  Ban duration in seconds
- `cleanup_interval`
  Expired-ban cleanup interval in seconds
- `ipv4_enabled`
  Enable IPv4 banning
- `ipv6_enabled`
  Enable IPv6 banning
- `fw4_table`
  Usually `fw4`
- `fw4_ban_set4`
  IPv4 fw4 ban set name
- `fw4_ban_set6`
  IPv6 fw4 ban set name
- `fw4_allow_set4`
  IPv4 fw4 whitelist set name
- `fw4_allow_set6`
  IPv6 fw4 whitelist set name
- `nft_family`
  Usually `inet`
- `nft_table`
  Custom nft table name for non-fw4 mode
- `nft_chain`
  Custom nft chain name for non-fw4 mode
- `nft_set4`
  IPv4 nft ban set name
- `nft_set6`
  IPv6 nft ban set name
- `nft_allow_set4`
  IPv4 nft whitelist set name
- `nft_allow_set6`
  IPv6 nft whitelist set name
- `fail_pattern`
  Repeated list option for failure log matching
- `ignore_ip`
  Repeated list option for whitelist IPs
- `ignore_net`
  Repeated list option for whitelist CIDRs

Example:

```uci
config logban 'main'
	option enabled '1'
	option backend 'logread'
	option firewall_backend 'auto'
	option find_time '300'
	option max_retry '5'
	option ban_time '3600'
	option cleanup_interval '30'
	option ipv4_enabled '1'
	option ipv6_enabled '1'

	list fail_pattern 'Bad password attempt for'
	list fail_pattern 'luci: failed login'

	list ignore_ip '127.0.0.1'
	list ignore_ip '::1'
	list ignore_net '192.168.1.0/24'
	list ignore_net 'fd00::/8'
```

## Raw Installation

Copy the files to an OpenWrt device:

```sh
scp files/usr/sbin/logban.sh root@router:/usr/sbin/logban.sh
scp files/etc/init.d/logban root@router:/etc/init.d/logban
scp files/etc/config/logban root@router:/etc/config/logban
ssh root@router 'chmod +x /usr/sbin/logban.sh /etc/init.d/logban && /etc/init.d/logban enable && /etc/init.d/logban restart'
```

## Build As OpenWrt Package

OpenWrt packages are built as `.ipk`, not Android-style `.apk`.

Copy `package/logban` into your OpenWrt SDK or source tree:

```sh
cp -r package/logban /path/to/openwrt/package/
cd /path/to/openwrt
make package/logban/compile V=s
```

The resulting package will appear under `bin/packages/*/*/`.

## Runtime Files

- `/var/run/logban`
  Runtime state, counters, and ban metadata
- `/etc/logban/banlist4`
  Persistent IPv4 bans in `fw4` mode
- `/etc/logban/banlist6`
  Persistent IPv6 bans in `fw4` mode
- `/usr/share/nftables.d/table-pre/90-logban-sets.nft`
  Generated fw4 nft set definitions
- `/usr/share/nftables.d/chain-pre/input/90-logban-rules.nft`
  Generated fw4 input-chain rules

## Service Management

```sh
/etc/init.d/logban enable
/etc/init.d/logban start
/etc/init.d/logban restart
/etc/init.d/logban stop
```

## Verification

Useful checks on the router:

```sh
logread -e logban
logread | grep -E 'dropbear|luci'
uci show logban
nft list ruleset | grep logban
cat /etc/logban/banlist4
cat /etc/logban/banlist6
```

## Limitations

- Matching is substring-based, not full regex-based
- Log formats vary across OpenWrt versions and custom images
- IPv6 extraction is designed for common `dropbear`/LuCI-style logs, but unusual formats may require adjustment
- `iptables` fallback is less feature-rich than `fw4`
- This project currently focuses on login-failure blocking, not broader intrusion heuristics

## Troubleshooting

- No bans are happening
  Check your actual logs first and make sure `fail_pattern` matches them
- Service starts but no firewall effect
  Verify whether the device is using `fw4`, raw `nft`, or legacy `iptables`
- Whitelist is not honored
  Check whether the address family matches and whether the entry is IP vs CIDR
- Ban disappears after reboot
  Use `fw4` mode instead of plain `nft` or `iptables`
- LuCI failures are not caught
  Inspect `logread` and add the exact LuCI failure string used by your build

## Notes

- `logread -f` is usually the best source on modern OpenWrt systems
- If your device writes auth logs into a file instead, switch to `backend='file'`
- If you are building for a very small target, verify that `nftables` and `firewall4` packages are available

## License

No license file is included yet. Add one before wider redistribution if you want clear reuse terms.

---

## 中文說明

`openwrt-logban` 是一個給 OpenWrt 使用的輕量級即時封鎖服務，用來監看認證失敗日誌，並在同一來源 IP 在一定時間內多次登入失敗時，自動把它封鎖。

它的定位是 OpenWrt 上偏實用、低資源占用的 `fail2ban` 替代方案。

## 功能

- 相容 BusyBox `ash`
- 可即時監看 `logread -f`，也可讀取指定日誌檔
- 內建 `dropbear` 與 `uhttpd/LuCI` 常見登入失敗匹配
- 支援 IPv4 與 IPv6
- 支援白名單 IP 與 CIDR 網段
- 優先使用 `fw4`，其次 `nftables`，最後回退到 `iptables`
- 支援暫時封鎖與自動解封
- 在 `fw4` 模式下可跨 `fw4 reload` 與重開機保留封鎖名單
- 內含 OpenWrt `ipk` 套件骨架

## 目錄結構

- `files/usr/sbin/logban.sh`
  主監控腳本
- `files/etc/init.d/logban`
  `procd` 服務啟動腳本
- `files/etc/config/logban`
  UCI 設定檔
- `package/logban`
  OpenWrt SDK 或原始碼樹可用的套件目錄

## 工作方式

`logban.sh` 會逐行讀取認證日誌。當某一行符合失敗模式時，程式會抽取來源 IP，檢查是否在白名單內，然後記錄該來源的失敗時間戳。

如果同一來源在 `find_time` 秒內失敗次數超過 `max_retry`，就會封鎖該 IP，封鎖時間為 `ban_time` 秒。

防火牆行為如下：

- `fw4` 模式
  立即以 `nft` 更新 runtime set，使封鎖立刻生效
- `fw4` 模式
  持久化 ban 名單寫入 `/etc/logban/banlist4` 與 `/etc/logban/banlist6`
- `fw4` 模式
  產生 `/usr/share/nftables.d/` 下的 nft snippets，供 `fw4 reload` 與開機後重建規則
- `nft` 模式
  使用獨立 nft table 與 sets
- `iptables` 模式
  使用 `iptables` / `ip6tables` chain 作為後備方案

## 預設匹配規則

預設包含以下常見 OpenWrt 認證失敗字串：

- `Bad password attempt for`
- `Failed password for`
- `Login attempt for nonexistent user`
- `Exit before auth from <`
- `luci: failed login`
- `luci: invalid password`
- `authentication failure`

這些規則主要覆蓋 `dropbear` 與 `uhttpd/LuCI` 的常見失敗日誌，但仍建議你用實機 `logread` 再核對一次。

## 預設白名單

預設包含：

- `127.0.0.1`
- `::1`
- `192.168.0.0/16`
- `10.0.0.0/8`
- `172.16.0.0/12`
- `fc00::/7`
- `fe80::/10`

請依你的實際網段調整。若你的流量前面還有代理、隧道或特殊拓撲，不要直接假設預設值一定正確。

## 設定方式

UCI 設定檔位置：

- `/etc/config/logban`

主要設定項目：

- `enabled`
  `1` 啟用，`0` 停用
- `backend`
  `logread` 或 `file`
- `log_file`
  當 `backend='file'` 時使用
- `firewall_backend`
  `auto`、`fw4`、`nft`、`iptables`
- `find_time`
  失敗統計時間窗，單位秒
- `max_retry`
  觸發封鎖前允許的失敗次數
- `ban_time`
  封鎖時間，單位秒
- `cleanup_interval`
  過期封鎖清理間隔，單位秒
- `ipv4_enabled`
  是否啟用 IPv4 封鎖
- `ipv6_enabled`
  是否啟用 IPv6 封鎖
- `fail_pattern`
  可重複定義的失敗匹配字串
- `ignore_ip`
  可重複定義的白名單 IP
- `ignore_net`
  可重複定義的白名單網段

## 直接部署

把檔案複製到 OpenWrt：

```sh
scp files/usr/sbin/logban.sh root@router:/usr/sbin/logban.sh
scp files/etc/init.d/logban root@router:/etc/init.d/logban
scp files/etc/config/logban root@router:/etc/config/logban
ssh root@router 'chmod +x /usr/sbin/logban.sh /etc/init.d/logban && /etc/init.d/logban enable && /etc/init.d/logban restart'
```

## 編譯成 OpenWrt 套件

OpenWrt 的安裝包格式是 `.ipk`，不是 Android 的 `.apk`。

把 `package/logban` 放進 OpenWrt SDK 或原始碼樹：

```sh
cp -r package/logban /path/to/openwrt/package/
cd /path/to/openwrt
make package/logban/compile V=s
```

產物會出現在 `bin/packages/*/*/`。

## 執行期檔案

- `/var/run/logban`
  執行期狀態、計數器、ban metadata
- `/etc/logban/banlist4`
  `fw4` 模式下的持久化 IPv4 ban 名單
- `/etc/logban/banlist6`
  `fw4` 模式下的持久化 IPv6 ban 名單
- `/usr/share/nftables.d/table-pre/90-logban-sets.nft`
  自動生成的 fw4 set 定義
- `/usr/share/nftables.d/chain-pre/input/90-logban-rules.nft`
  自動生成的 fw4 input 規則

## 服務管理

```sh
/etc/init.d/logban enable
/etc/init.d/logban start
/etc/init.d/logban restart
/etc/init.d/logban stop
```

## 驗證方式

在路由器上可用：

```sh
logread -e logban
logread | grep -E 'dropbear|luci'
uci show logban
nft list ruleset | grep logban
cat /etc/logban/banlist4
cat /etc/logban/banlist6
```

## 限制

- 目前是子字串匹配，不是完整 regex 引擎
- 不同 OpenWrt 版本與客製映像的日誌格式可能不同
- IPv6 抽取已針對常見 `dropbear` / LuCI 格式處理，但特殊格式仍可能要調整
- `iptables` 後備模式的功能不如 `fw4`
- 目前專注在登入失敗封鎖，不是完整入侵防護框架

## 疑難排解

- 有日誌但沒有封鎖
  先用實際 `logread` 確認 `fail_pattern` 是否真的匹配
- 服務有啟動但防火牆沒效果
  先確認設備實際是 `fw4`、原生 `nft` 還是舊版 `iptables`
- 白名單沒有生效
  檢查地址族別是否正確，以及你填的是單一 IP 還是 CIDR
- 重開機後 ban 消失
  請優先使用 `fw4` 模式
- LuCI 登入失敗沒有抓到
  直接看你的 `logread`，把真實失敗字串加進 `fail_pattern`

## 備註

- 在大多數現代 OpenWrt 上，`logread -f` 通常比直接盯檔案更可靠
- 若你的系統真的把認證日誌寫入檔案，再改用 `backend='file'`
- 若設備資源很小，請先確認有 `firewall4` 與 `nftables` 可用

## 授權

目前尚未附上 `LICENSE` 檔案。若你準備公開散佈或讓他人重用，建議補上明確授權條款。
