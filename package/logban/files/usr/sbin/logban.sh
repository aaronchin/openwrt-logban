#!/bin/sh

STATE_DIR="/var/run/logban"
FAIL_DIR="$STATE_DIR/failures"
BAN_DIR="$STATE_DIR/bans"
PID_FILE="$STATE_DIR/cleanup.pid"

PERSIST_DIR="/etc/logban"
BANLIST4_FILE="$PERSIST_DIR/banlist4"
BANLIST6_FILE="$PERSIST_DIR/banlist6"
FW4_TABLE_FILE="/usr/share/nftables.d/table-pre/90-logban-sets.nft"
FW4_CHAIN_FILE="/usr/share/nftables.d/chain-pre/input/90-logban-rules.nft"

DEFAULT_BACKEND="logread"
DEFAULT_LOG_FILE="/var/log/auth.log"
DEFAULT_FIREWALL_BACKEND="auto"
DEFAULT_FIND_TIME=300
DEFAULT_MAX_RETRY=5
DEFAULT_BAN_TIME=3600
DEFAULT_CLEANUP_INTERVAL=30
DEFAULT_IPV4_ENABLED=1
DEFAULT_IPV6_ENABLED=1
DEFAULT_FW4_TABLE="fw4"
DEFAULT_FW4_BAN_SET4="logban4"
DEFAULT_FW4_BAN_SET6="logban6"
DEFAULT_FW4_ALLOW_SET4="logban4_allow"
DEFAULT_FW4_ALLOW_SET6="logban6_allow"
DEFAULT_NFT_FAMILY="inet"
DEFAULT_NFT_TABLE="logban"
DEFAULT_NFT_CHAIN="input"
DEFAULT_NFT_SET4="blocked_ipv4"
DEFAULT_NFT_SET6="blocked_ipv6"
DEFAULT_NFT_ALLOW_SET4="allowed_ipv4"
DEFAULT_NFT_ALLOW_SET6="allowed_ipv6"

BACKEND="$DEFAULT_BACKEND"
LOG_FILE="$DEFAULT_LOG_FILE"
FIREWALL_BACKEND="$DEFAULT_FIREWALL_BACKEND"
FIND_TIME="$DEFAULT_FIND_TIME"
MAX_RETRY="$DEFAULT_MAX_RETRY"
BAN_TIME="$DEFAULT_BAN_TIME"
CLEANUP_INTERVAL="$DEFAULT_CLEANUP_INTERVAL"
IPV4_ENABLED="$DEFAULT_IPV4_ENABLED"
IPV6_ENABLED="$DEFAULT_IPV6_ENABLED"
FW4_TABLE="$DEFAULT_FW4_TABLE"
FW4_BAN_SET4="$DEFAULT_FW4_BAN_SET4"
FW4_BAN_SET6="$DEFAULT_FW4_BAN_SET6"
FW4_ALLOW_SET4="$DEFAULT_FW4_ALLOW_SET4"
FW4_ALLOW_SET6="$DEFAULT_FW4_ALLOW_SET6"
NFT_FAMILY="$DEFAULT_NFT_FAMILY"
NFT_TABLE="$DEFAULT_NFT_TABLE"
NFT_CHAIN="$DEFAULT_NFT_CHAIN"
NFT_SET4="$DEFAULT_NFT_SET4"
NFT_SET6="$DEFAULT_NFT_SET6"
NFT_ALLOW_SET4="$DEFAULT_NFT_ALLOW_SET4"
NFT_ALLOW_SET6="$DEFAULT_NFT_ALLOW_SET6"
FAIL_PATTERNS=""
IGNORE_ENTRIES=""

log() {
	logger -t logban "$*"
}

safe_name() {
	echo "$1" | tr '.:%/' '____'
}

is_number() {
	case "$1" in
		''|*[!0-9]*) return 1 ;;
		*) return 0 ;;
	esac
}

append_line() {
	local current="$1"
	local value="$2"

	if [ -z "$current" ]; then
		printf '%s' "$value"
	else
		printf '%s\n%s' "$current" "$value"
	fi
}

is_ipv4() {
	echo "$1" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}(/([0-9]|[12][0-9]|3[0-2]))?$'
}

is_ipv6() {
	echo "$1" | grep -Eq '^[0-9A-Fa-f:]+(%[A-Za-z0-9_.-]+)?(/[0-9]{1,3})?$'
}

ip_family() {
	case "$1" in
		*:* ) echo 6 ;;
		*.* ) echo 4 ;;
		* ) echo 0 ;;
	esac
}

load_config() {
	[ -f /lib/functions.sh ] || return 0
	. /lib/functions.sh

	config_load logban
	config_get enabled main enabled 1
	config_get BACKEND main backend "$DEFAULT_BACKEND"
	config_get LOG_FILE main log_file "$DEFAULT_LOG_FILE"
	config_get FIREWALL_BACKEND main firewall_backend "$DEFAULT_FIREWALL_BACKEND"
	config_get FIND_TIME main find_time "$DEFAULT_FIND_TIME"
	config_get MAX_RETRY main max_retry "$DEFAULT_MAX_RETRY"
	config_get BAN_TIME main ban_time "$DEFAULT_BAN_TIME"
	config_get CLEANUP_INTERVAL main cleanup_interval "$DEFAULT_CLEANUP_INTERVAL"
	config_get IPV4_ENABLED main ipv4_enabled "$DEFAULT_IPV4_ENABLED"
	config_get IPV6_ENABLED main ipv6_enabled "$DEFAULT_IPV6_ENABLED"
	config_get FW4_TABLE main fw4_table "$DEFAULT_FW4_TABLE"
	config_get FW4_BAN_SET4 main fw4_ban_set4 "$DEFAULT_FW4_BAN_SET4"
	config_get FW4_BAN_SET6 main fw4_ban_set6 "$DEFAULT_FW4_BAN_SET6"
	config_get FW4_ALLOW_SET4 main fw4_allow_set4 "$DEFAULT_FW4_ALLOW_SET4"
	config_get FW4_ALLOW_SET6 main fw4_allow_set6 "$DEFAULT_FW4_ALLOW_SET6"
	config_get NFT_FAMILY main nft_family "$DEFAULT_NFT_FAMILY"
	config_get NFT_TABLE main nft_table "$DEFAULT_NFT_TABLE"
	config_get NFT_CHAIN main nft_chain "$DEFAULT_NFT_CHAIN"
	config_get NFT_SET4 main nft_set4 "$DEFAULT_NFT_SET4"
	config_get NFT_SET6 main nft_set6 "$DEFAULT_NFT_SET6"
	config_get NFT_ALLOW_SET4 main nft_allow_set4 "$DEFAULT_NFT_ALLOW_SET4"
	config_get NFT_ALLOW_SET6 main nft_allow_set6 "$DEFAULT_NFT_ALLOW_SET6"

	FAIL_PATTERNS=""
	IGNORE_ENTRIES=""

	config_list_foreach main fail_pattern add_fail_pattern
	config_list_foreach main ignore_ip add_ignore_entry
	config_list_foreach main ignore_net add_ignore_entry

	[ "$enabled" = "1" ] || exit 0
}

add_fail_pattern() {
	FAIL_PATTERNS="$(append_line "$FAIL_PATTERNS" "$1")"
}

add_ignore_entry() {
	IGNORE_ENTRIES="$(append_line "$IGNORE_ENTRIES" "$1")"
}

normalize_settings() {
	is_number "$FIND_TIME" || FIND_TIME="$DEFAULT_FIND_TIME"
	is_number "$MAX_RETRY" || MAX_RETRY="$DEFAULT_MAX_RETRY"
	is_number "$BAN_TIME" || BAN_TIME="$DEFAULT_BAN_TIME"
	is_number "$CLEANUP_INTERVAL" || CLEANUP_INTERVAL="$DEFAULT_CLEANUP_INTERVAL"

	[ "$CLEANUP_INTERVAL" -gt 0 ] || CLEANUP_INTERVAL="$DEFAULT_CLEANUP_INTERVAL"
	[ "$MAX_RETRY" -gt 0 ] || MAX_RETRY="$DEFAULT_MAX_RETRY"
	[ "$FIND_TIME" -gt 0 ] || FIND_TIME="$DEFAULT_FIND_TIME"
	[ "$BAN_TIME" -gt 0 ] || BAN_TIME="$DEFAULT_BAN_TIME"

	case "$IPV4_ENABLED" in
		1|0) ;;
		*) IPV4_ENABLED="$DEFAULT_IPV4_ENABLED" ;;
	esac
	case "$IPV6_ENABLED" in
		1|0) ;;
		*) IPV6_ENABLED="$DEFAULT_IPV6_ENABLED" ;;
	esac

	if [ -z "$FAIL_PATTERNS" ]; then
		FAIL_PATTERNS="Bad password attempt for
Failed password for
Login attempt for nonexistent user
Exit before auth from <
luci: failed login
luci: invalid password
authentication failure"
	fi

	if [ -z "$IGNORE_ENTRIES" ]; then
		IGNORE_ENTRIES="127.0.0.1
::1"
	fi
}

prepare_state() {
	mkdir -p "$FAIL_DIR" "$BAN_DIR" "$PERSIST_DIR"
	[ -f "$BANLIST4_FILE" ] || : > "$BANLIST4_FILE"
	[ -f "$BANLIST6_FILE" ] || : > "$BANLIST6_FILE"
}

pick_firewall_backend() {
	if [ "$FIREWALL_BACKEND" = "auto" ]; then
		if command -v fw4 >/dev/null 2>&1; then
			FIREWALL_BACKEND="fw4"
		elif command -v nft >/dev/null 2>&1; then
			FIREWALL_BACKEND="nft"
		elif command -v iptables >/dev/null 2>&1; then
			FIREWALL_BACKEND="iptables"
		else
			log "no supported firewall backend found"
			return 1
		fi
	fi

	case "$FIREWALL_BACKEND" in
		fw4|nft|iptables) return 0 ;;
		*) log "unsupported firewall backend: $FIREWALL_BACKEND"; return 1 ;;
	esac
}

update_file_if_changed() {
	local target="$1"
	local tmp="$2"

	if [ -f "$target" ] && cmp -s "$target" "$tmp" >/dev/null 2>&1; then
		rm -f "$tmp"
		return 1
	fi

	mv "$tmp" "$target"
	return 0
}

render_elements_from_file() {
	local family="$1"
	local file="$2"
	local old_ifs="$IFS"
	local line output=""

	[ -f "$file" ] || return 0
	IFS='
'
	for line in $(cat "$file"); do
		[ -n "$line" ] || continue
		case "$family" in
			4) is_ipv4 "$line" || continue ;;
			6) is_ipv6 "$line" || continue ;;
			*) continue ;;
		esac
		if [ -z "$output" ]; then
			output="$line"
		else
			output="$output, $line"
		fi
	done
	IFS="$old_ifs"

	[ -n "$output" ] && printf '%s' "$output"
}

render_elements_from_list() {
	local family="$1"
	local old_ifs="$IFS"
	local line output=""

	IFS='
'
	for line in $IGNORE_ENTRIES; do
		[ -n "$line" ] || continue
		case "$family" in
			4) is_ipv4 "$line" || continue ;;
			6) is_ipv6 "$line" || continue ;;
			*) continue ;;
		esac
		if [ -z "$output" ]; then
			output="$line"
		else
			output="$output, $line"
		fi
	done
	IFS="$old_ifs"

	[ -n "$output" ] && printf '%s' "$output"
}

write_nft_set_block() {
	local file="$1"
	local set_name="$2"
	local set_type="$3"
	local elements="$4"

	{
		echo "set $set_name {"
		echo "	type $set_type"
		echo "	flags interval"
		if [ -n "$elements" ]; then
			echo "	elements = { $elements }"
		fi
		echo "}"
	} >> "$file"
}

sync_fw4_files() {
	local changed=1
	local tmp_table tmp_chain
	local ban4 ban6 allow4 allow6

	mkdir -p "$(dirname "$FW4_TABLE_FILE")" "$(dirname "$FW4_CHAIN_FILE")"
	tmp_table="$STATE_DIR/fw4-table.$$"
	tmp_chain="$STATE_DIR/fw4-chain.$$"

	ban4="$(render_elements_from_file 4 "$BANLIST4_FILE")"
	ban6="$(render_elements_from_file 6 "$BANLIST6_FILE")"
	allow4="$(render_elements_from_list 4)"
	allow6="$(render_elements_from_list 6)"

	: > "$tmp_table"
	[ "$IPV4_ENABLED" = "1" ] && {
		write_nft_set_block "$tmp_table" "$FW4_BAN_SET4" "ipv4_addr" "$ban4"
		write_nft_set_block "$tmp_table" "$FW4_ALLOW_SET4" "ipv4_addr" "$allow4"
	}
	[ "$IPV6_ENABLED" = "1" ] && {
		write_nft_set_block "$tmp_table" "$FW4_BAN_SET6" "ipv6_addr" "$ban6"
		write_nft_set_block "$tmp_table" "$FW4_ALLOW_SET6" "ipv6_addr" "$allow6"
	}

	: > "$tmp_chain"
	[ "$IPV4_ENABLED" = "1" ] && echo "ip saddr @$FW4_BAN_SET4 drop" >> "$tmp_chain"
	[ "$IPV6_ENABLED" = "1" ] && echo "ip6 saddr @$FW4_BAN_SET6 drop" >> "$tmp_chain"

	update_file_if_changed "$FW4_TABLE_FILE" "$tmp_table" && changed=0
	update_file_if_changed "$FW4_CHAIN_FILE" "$tmp_chain" && changed=0

	return "$changed"
}

ensure_fw4_loaded() {
	nft list table inet "$FW4_TABLE" >/dev/null 2>&1 || fw4 reload >/dev/null 2>&1

	if [ "$IPV4_ENABLED" = "1" ]; then
		nft list set inet "$FW4_TABLE" "$FW4_BAN_SET4" >/dev/null 2>&1 || fw4 reload >/dev/null 2>&1
		nft list set inet "$FW4_TABLE" "$FW4_ALLOW_SET4" >/dev/null 2>&1 || fw4 reload >/dev/null 2>&1
	fi
	if [ "$IPV6_ENABLED" = "1" ]; then
		nft list set inet "$FW4_TABLE" "$FW4_BAN_SET6" >/dev/null 2>&1 || fw4 reload >/dev/null 2>&1
		nft list set inet "$FW4_TABLE" "$FW4_ALLOW_SET6" >/dev/null 2>&1 || fw4 reload >/dev/null 2>&1
	fi
}

setup_fw4() {
	local changed=1

	sync_fw4_files
	changed="$?"
	if [ "$changed" -eq 0 ]; then
		fw4 reload >/dev/null 2>&1 || return 1
	fi

	ensure_fw4_loaded

	if [ "$IPV4_ENABLED" = "1" ]; then
		nft list set inet "$FW4_TABLE" "$FW4_BAN_SET4" >/dev/null 2>&1 || return 1
		nft list set inet "$FW4_TABLE" "$FW4_ALLOW_SET4" >/dev/null 2>&1 || return 1
	fi
	if [ "$IPV6_ENABLED" = "1" ]; then
		nft list set inet "$FW4_TABLE" "$FW4_BAN_SET6" >/dev/null 2>&1 || return 1
		nft list set inet "$FW4_TABLE" "$FW4_ALLOW_SET6" >/dev/null 2>&1 || return 1
	fi
}

setup_nft() {
	nft list table "$NFT_FAMILY" "$NFT_TABLE" >/dev/null 2>&1 || nft add table "$NFT_FAMILY" "$NFT_TABLE" || return 1
	nft list chain "$NFT_FAMILY" "$NFT_TABLE" "$NFT_CHAIN" >/dev/null 2>&1 || \
		nft add chain "$NFT_FAMILY" "$NFT_TABLE" "$NFT_CHAIN" "{ type filter hook input priority -10; policy accept; }" || return 1

	if [ "$IPV4_ENABLED" = "1" ]; then
		nft list set "$NFT_FAMILY" "$NFT_TABLE" "$NFT_SET4" >/dev/null 2>&1 || \
			nft add set "$NFT_FAMILY" "$NFT_TABLE" "$NFT_SET4" "{ type ipv4_addr; flags interval; }" || return 1
		nft list set "$NFT_FAMILY" "$NFT_TABLE" "$NFT_ALLOW_SET4" >/dev/null 2>&1 || \
			nft add set "$NFT_FAMILY" "$NFT_TABLE" "$NFT_ALLOW_SET4" "{ type ipv4_addr; flags interval; }" || return 1
		nft list chain "$NFT_FAMILY" "$NFT_TABLE" "$NFT_CHAIN" 2>/dev/null | grep -q "@$NFT_SET4 drop" || \
			nft add rule "$NFT_FAMILY" "$NFT_TABLE" "$NFT_CHAIN" ip saddr "@$NFT_SET4" drop || return 1
	fi

	if [ "$IPV6_ENABLED" = "1" ]; then
		nft list set "$NFT_FAMILY" "$NFT_TABLE" "$NFT_SET6" >/dev/null 2>&1 || \
			nft add set "$NFT_FAMILY" "$NFT_TABLE" "$NFT_SET6" "{ type ipv6_addr; flags interval; }" || return 1
		nft list set "$NFT_FAMILY" "$NFT_TABLE" "$NFT_ALLOW_SET6" >/dev/null 2>&1 || \
			nft add set "$NFT_FAMILY" "$NFT_TABLE" "$NFT_ALLOW_SET6" "{ type ipv6_addr; flags interval; }" || return 1
		nft list chain "$NFT_FAMILY" "$NFT_TABLE" "$NFT_CHAIN" 2>/dev/null | grep -q "@$NFT_SET6 drop" || \
			nft add rule "$NFT_FAMILY" "$NFT_TABLE" "$NFT_CHAIN" ip6 saddr "@$NFT_SET6" drop || return 1
	fi

	load_allow_entries_into_nft
}

load_allow_entries_into_nft() {
	local old_ifs="$IFS"
	local entry family

	IFS='
'
	for entry in $IGNORE_ENTRIES; do
		[ -n "$entry" ] || continue
		family="$(ip_family "$entry")"
		case "$family" in
			4)
				[ "$IPV4_ENABLED" = "1" ] || continue
				nft add element "$NFT_FAMILY" "$NFT_TABLE" "$NFT_ALLOW_SET4" "{ $entry }" >/dev/null 2>&1 || true
				;;
			6)
				[ "$IPV6_ENABLED" = "1" ] || continue
				nft add element "$NFT_FAMILY" "$NFT_TABLE" "$NFT_ALLOW_SET6" "{ $entry }" >/dev/null 2>&1 || true
				;;
		esac
	done
	IFS="$old_ifs"
}

setup_iptables() {
	iptables -L LOGBAN >/dev/null 2>&1 || iptables -N LOGBAN || return 1
	iptables -C INPUT -j LOGBAN >/dev/null 2>&1 || iptables -I INPUT 1 -j LOGBAN || return 1

	if [ "$IPV6_ENABLED" = "1" ] && command -v ip6tables >/dev/null 2>&1; then
		ip6tables -L LOGBAN >/dev/null 2>&1 || ip6tables -N LOGBAN || return 1
		ip6tables -C INPUT -j LOGBAN >/dev/null 2>&1 || ip6tables -I INPUT 1 -j LOGBAN || return 1
	fi
}

setup_firewall() {
	case "$FIREWALL_BACKEND" in
		fw4) setup_fw4 ;;
		nft) setup_nft ;;
		iptables) setup_iptables ;;
	esac
}

firewall_has_ip() {
	local ip="$1"
	local family="$2"

	case "$FIREWALL_BACKEND" in
		fw4)
			case "$family" in
				4) nft get element inet "$FW4_TABLE" "$FW4_BAN_SET4" "{ $ip }" >/dev/null 2>&1 ;;
				6) nft get element inet "$FW4_TABLE" "$FW4_BAN_SET6" "{ $ip }" >/dev/null 2>&1 ;;
				*) return 1 ;;
			esac
			;;
		nft)
			case "$family" in
				4) nft get element "$NFT_FAMILY" "$NFT_TABLE" "$NFT_SET4" "{ $ip }" >/dev/null 2>&1 ;;
				6) nft get element "$NFT_FAMILY" "$NFT_TABLE" "$NFT_SET6" "{ $ip }" >/dev/null 2>&1 ;;
				*) return 1 ;;
			esac
			;;
		iptables)
			case "$family" in
				4) iptables -C LOGBAN -s "$ip" -j DROP >/dev/null 2>&1 ;;
				6) ip6tables -C LOGBAN -s "$ip" -j DROP >/dev/null 2>&1 ;;
				*) return 1 ;;
			esac
			;;
	esac
}

firewall_ban_ip() {
	local ip="$1"
	local family="$2"

	case "$FIREWALL_BACKEND" in
		fw4)
			case "$family" in
				4) firewall_has_ip "$ip" 4 || nft add element inet "$FW4_TABLE" "$FW4_BAN_SET4" "{ $ip }" >/dev/null 2>&1 ;;
				6) firewall_has_ip "$ip" 6 || nft add element inet "$FW4_TABLE" "$FW4_BAN_SET6" "{ $ip }" >/dev/null 2>&1 ;;
			esac
			;;
		nft)
			case "$family" in
				4) firewall_has_ip "$ip" 4 || nft add element "$NFT_FAMILY" "$NFT_TABLE" "$NFT_SET4" "{ $ip }" >/dev/null 2>&1 ;;
				6) firewall_has_ip "$ip" 6 || nft add element "$NFT_FAMILY" "$NFT_TABLE" "$NFT_SET6" "{ $ip }" >/dev/null 2>&1 ;;
			esac
			;;
		iptables)
			case "$family" in
				4) firewall_has_ip "$ip" 4 || iptables -I LOGBAN -s "$ip" -j DROP >/dev/null 2>&1 ;;
				6) firewall_has_ip "$ip" 6 || ip6tables -I LOGBAN -s "$ip" -j DROP >/dev/null 2>&1 ;;
			esac
			;;
	esac
}

firewall_unban_ip() {
	local ip="$1"
	local family="$2"

	case "$FIREWALL_BACKEND" in
		fw4)
			case "$family" in
				4) firewall_has_ip "$ip" 4 && nft delete element inet "$FW4_TABLE" "$FW4_BAN_SET4" "{ $ip }" >/dev/null 2>&1 ;;
				6) firewall_has_ip "$ip" 6 && nft delete element inet "$FW4_TABLE" "$FW4_BAN_SET6" "{ $ip }" >/dev/null 2>&1 ;;
			esac
			;;
		nft)
			case "$family" in
				4) firewall_has_ip "$ip" 4 && nft delete element "$NFT_FAMILY" "$NFT_TABLE" "$NFT_SET4" "{ $ip }" >/dev/null 2>&1 ;;
				6) firewall_has_ip "$ip" 6 && nft delete element "$NFT_FAMILY" "$NFT_TABLE" "$NFT_SET6" "{ $ip }" >/dev/null 2>&1 ;;
			esac
			;;
		iptables)
			case "$family" in
				4)
					while iptables -C LOGBAN -s "$ip" -j DROP >/dev/null 2>&1; do
						iptables -D LOGBAN -s "$ip" -j DROP >/dev/null 2>&1 || break
					done
					;;
				6)
					while ip6tables -C LOGBAN -s "$ip" -j DROP >/dev/null 2>&1; do
						ip6tables -D LOGBAN -s "$ip" -j DROP >/dev/null 2>&1 || break
					done
					;;
			esac
			;;
	esac
}

persist_ban_ip() {
	local ip="$1"
	local family="$2"
	local file

	case "$family" in
		4) file="$BANLIST4_FILE" ;;
		6) file="$BANLIST6_FILE" ;;
		*) return 1 ;;
	esac

	grep -Fxq "$ip" "$file" 2>/dev/null || echo "$ip" >> "$file"
	[ "$FIREWALL_BACKEND" = "fw4" ] && sync_fw4_files >/dev/null 2>&1
}

remove_persisted_ban_ip() {
	local ip="$1"
	local family="$2"
	local file tmp

	case "$family" in
		4) file="$BANLIST4_FILE" ;;
		6) file="$BANLIST6_FILE" ;;
		*) return 1 ;;
	esac

	tmp="$STATE_DIR/banlist.$$"
	grep -Fvx "$ip" "$file" > "$tmp" 2>/dev/null || : > "$tmp"
	mv "$tmp" "$file"
	[ "$FIREWALL_BACKEND" = "fw4" ] && sync_fw4_files >/dev/null 2>&1
}

is_ignored_ip() {
	local ip="$1"
	local family="$2"

	case "$FIREWALL_BACKEND" in
		fw4)
			case "$family" in
				4) nft get element inet "$FW4_TABLE" "$FW4_ALLOW_SET4" "{ $ip }" >/dev/null 2>&1 ;;
				6) nft get element inet "$FW4_TABLE" "$FW4_ALLOW_SET6" "{ $ip }" >/dev/null 2>&1 ;;
				*) return 1 ;;
			esac
			;;
		nft)
			case "$family" in
				4) nft get element "$NFT_FAMILY" "$NFT_TABLE" "$NFT_ALLOW_SET4" "{ $ip }" >/dev/null 2>&1 ;;
				6) nft get element "$NFT_FAMILY" "$NFT_TABLE" "$NFT_ALLOW_SET6" "{ $ip }" >/dev/null 2>&1 ;;
				*) return 1 ;;
			esac
			;;
		iptables)
			grep -Fxq "$ip" <<EOF
$IGNORE_ENTRIES
EOF
			;;
	esac
}

normalize_candidate() {
	local token="$1"

	token="${token#<}"
	token="${token#(}"
	token="${token#[}"
	token="${token%\>}"
	token="${token%)}"
	token="${token%]}"
	token="${token%,}"
	token="${token%;}"
	token="${token%:}"

	case "$token" in
		\[*\]:*)
			token="${token#\[}"
			token="${token%%]*}"
			;;
	esac

	case "$token" in
		*%*)
			token="${token%%%*}"
			;;
	esac

	if echo "$token" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}:[0-9]+$'; then
		token="${token%:*}"
	fi

	echo "$token"
}

extract_ip() {
	local line="$1"
	local token ip

	token="$(echo "$line" | sed -n 's/.*from[[:space:]]\+\([^[:space:]]*\).*/\1/p' | head -n 1)"
	ip="$(normalize_candidate "$token")"

	if is_ipv4 "$ip" || is_ipv6 "$ip"; then
		echo "$ip"
		return 0
	fi

	ip="$(echo "$line" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | tail -n 1)"
	if is_ipv4 "$ip"; then
		echo "$ip"
		return 0
	fi

	ip="$(echo "$line" | grep -Eo '\[[0-9A-Fa-f:%._-]+\]' | head -n 1 | tr -d '[]')"
	ip="$(normalize_candidate "$ip")"
	if is_ipv6 "$ip"; then
		echo "$ip"
		return 0
	fi

	ip="$(echo "$line" | grep -Eo '([0-9A-Fa-f]{0,4}:){2,}[0-9A-Fa-f:%._-]+' | head -n 1)"
	ip="$(normalize_candidate "$ip")"
	if is_ipv6 "$ip"; then
		echo "$ip"
		return 0
	fi

	return 1
}

line_matches_failure() {
	local line="$1"
	local pattern old_ifs="$IFS"

	IFS='
'
	for pattern in $FAIL_PATTERNS; do
		[ -n "$pattern" ] || continue
		echo "$line" | grep -Fq "$pattern" && {
			IFS="$old_ifs"
			return 0
		}
	done
	IFS="$old_ifs"

	return 1
}

prune_failures() {
	local file="$1"
	local cutoff="$2"
	local tmp

	[ -f "$file" ] || return 0
	tmp="${file}.tmp"
	awk -v cutoff="$cutoff" '$1 >= cutoff { print $1 }' "$file" > "$tmp" 2>/dev/null
	mv "$tmp" "$file"
}

count_failures() {
	local file="$1"

	[ -f "$file" ] || {
		echo 0
		return
	}

	wc -l < "$file" | tr -d ' '
}

ban_ip() {
	local ip="$1"
	local family="$2"
	local now="$3"
	local expire
	local file

	is_ignored_ip "$ip" "$family" && return 0
	file="$BAN_DIR/$(safe_name "$ip").ban"
	expire=$((now + BAN_TIME))

	firewall_ban_ip "$ip" "$family"
	persist_ban_ip "$ip" "$family"
	echo "$expire $family $ip" > "$file"
	log "banned $ip family=$family until $expire"
}

unban_ip() {
	local ip="$1"
	local family="$2"
	local file="$BAN_DIR/$(safe_name "$ip").ban"

	firewall_unban_ip "$ip" "$family"
	remove_persisted_ban_ip "$ip" "$family"
	rm -f "$file"
	log "unbanned $ip family=$family"
}

handle_failure() {
	local line="$1"
	local now ip fail_file cutoff count family

	line_matches_failure "$line" || return 0
	ip="$(extract_ip "$line")"
	[ -n "$ip" ] || return 0
	family="$(ip_family "$ip")"

	case "$family" in
		4) [ "$IPV4_ENABLED" = "1" ] || return 0 ;;
		6) [ "$IPV6_ENABLED" = "1" ] || return 0 ;;
		*) return 0 ;;
	esac

	is_ignored_ip "$ip" "$family" && return 0

	now="$(date +%s)"
	fail_file="$FAIL_DIR/$(safe_name "$ip").fail"
	cutoff=$((now - FIND_TIME))

	[ -f "$fail_file" ] || : > "$fail_file"
	echo "$now" >> "$fail_file"
	prune_failures "$fail_file" "$cutoff"
	count="$(count_failures "$fail_file")"

	if [ "$count" -ge "$MAX_RETRY" ]; then
		if [ ! -f "$BAN_DIR/$(safe_name "$ip").ban" ]; then
			ban_ip "$ip" "$family" "$now"
		fi
		: > "$fail_file"
	fi
}

cleanup_expired_bans() {
	local now file expire ip family

	now="$(date +%s)"
	for file in "$BAN_DIR"/*.ban; do
		[ -f "$file" ] || continue
		expire="$(awk '{ print $1 }' "$file" 2>/dev/null)"
		family="$(awk '{ print $2 }' "$file" 2>/dev/null)"
		ip="$(awk '{ print $3 }' "$file" 2>/dev/null)"
		is_number "$expire" || {
			rm -f "$file"
			continue
		}
		case "$family" in
			4|6) ;;
			*) rm -f "$file"; continue ;;
		esac
		[ -n "$ip" ] || {
			rm -f "$file"
			continue
		}
		if [ "$expire" -le "$now" ]; then
			unban_ip "$ip" "$family"
		fi
	done
}

cleanup_loop() {
	while true; do
		cleanup_expired_bans
		sleep "$CLEANUP_INTERVAL"
	done
}

stop_cleanup_loop() {
	if [ -f "$PID_FILE" ]; then
		kill "$(cat "$PID_FILE" 2>/dev/null)" >/dev/null 2>&1
		rm -f "$PID_FILE"
	fi
}

monitor_logread() {
	logread -f | while IFS= read -r line; do
		handle_failure "$line"
	done
}

monitor_file() {
	[ -f "$LOG_FILE" ] || {
		log "log file not found: $LOG_FILE"
		return 1
	}

	tail -f "$LOG_FILE" | while IFS= read -r line; do
		handle_failure "$line"
	done
}

run() {
	load_config
	normalize_settings
	prepare_state
	pick_firewall_backend || exit 1
	setup_firewall || exit 1

	cleanup_loop &
	echo "$!" > "$PID_FILE"
	trap 'stop_cleanup_loop; exit 0' INT TERM

	case "$BACKEND" in
		logread) monitor_logread ;;
		file) monitor_file ;;
		*) log "unsupported backend: $BACKEND"; stop_cleanup_loop; exit 1 ;;
	esac
}

stop_all() {
	stop_cleanup_loop
}

case "$1" in
	run) run ;;
	stop) stop_all ;;
	*)
		echo "usage: $0 {run|stop}" >&2
		exit 1
		;;
esac
