#!/usr/bin/env bash
# Source from quick-start.sh. Compare macOS bridge ARP snapshots and confirm via SSH.
set -Eeuo pipefail

# Produce normalized 'ip mac' pairs, excluding incomplete/broadcast entries.
arp_pairs() {
  local iface="${F4M_BRIDGE:-bridge100}" line ip mac
  while IFS= read -r line; do
    [[ "$line" =~ \(([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\) ]] || continue
    ip="${BASH_REMATCH[1]}"
    [[ "$line" =~ [[:space:]]at[[:space:]]([0-9a-fA-F:]+)[[:space:]] ]] || continue
    mac="${BASH_REMATCH[1]}"
    printf '%s %s\n' "$ip" "$(normalize_mac "$mac")"
  done < <(arp -an -i "$iface" 2>/dev/null || true)
}
normalize_mac() {
  local mac="$1" piece result='' hex
  local IFS=:
  for piece in $mac; do
    [[ "$piece" =~ ^[0-9a-fA-F]{1,2}$ ]] || return 1
    printf -v hex '%02x' "$((16#$piece))"
    result+="${result:+:}$hex"
  done
  printf '%s\n' "$result"
}
vm_mac() {
  osascript - "$F4M_VM_NAME" <<'APPLESCRIPT' 2>/dev/null
on run argv
  tell application "UTM"
    set vm to virtual machine named (item 1 of argv)
    set netDevices to network interfaces of (configuration of vm)
    return address of item 1 of netDevices
  end tell
end run
APPLESCRIPT
}
# Verify the guest identity, not simply that a port is open.
probe_ip() {
  local ip="$1" result
  [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  result="$(ssh -i "$F4M_KEY" -p 22 -o BatchMode=yes -o ConnectTimeout=3 \
    -o ConnectionAttempts=1 -o StrictHostKeyChecking=accept-new \
    "flatpak@$ip" 'printf "%s:%s" "$(id -un)" "$(hostname -s)"' 2>/dev/null)" || return 1
  [[ "$result" == 'flatpak:flatpak-utm' ]]
}
# ARP is a cache: probe the recent VM DHCP lease IPs to refresh neighbours.
refresh_lease_neighbours() {
  local lease ip
  [[ -r /var/db/dhcpd_leases ]] || return 0
  while IFS= read -r ip; do
    [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
    ping -c 1 -W 200 "$ip" >/dev/null 2>&1 &
  done < <(awk -F= '/^[[:space:]]*ip_address=/{gsub(/[[:space:]]/,"",$2);print $2}' /var/db/dhcpd_leases | sort -u)
  wait || true
}
# Input: a pre-start snapshot (ip mac lines), output: validated IP.
discover_arp_ip() {
  local before="$1" mac after ip line original
  mac="$(vm_mac 2>/dev/null || true)"
  if [[ -n "$mac" ]]; then mac="$(normalize_mac "$mac" 2>/dev/null || true)"; fi
  refresh_lease_neighbours
  after="$(arp_pairs)"
  # Matching MAC overrides ARP-difference heuristics, including existing entries.
  if [[ -n "$mac" ]]; then
    while read -r ip line; do
      [[ "$line" == "$mac" ]] || continue
      if probe_ip "$ip"; then printf '%s\n' "$ip"; return 0; fi
    done <<< "$after"
  fi
  # Only check new entries; SSH verifies user and hostname.
  while read -r ip line; do
    [[ -n "$ip" ]] || continue
    if ! grep -Fqx "$ip $line" <<< "$before"; then
      if probe_ip "$ip"; then printf '%s\n' "$ip"; return 0; fi
    fi
  done <<< "$after"
  return 1
}
