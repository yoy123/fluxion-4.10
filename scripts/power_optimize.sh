#!/usr/bin/env bash
# Optimize TX power for interfaces used during evil twin style attacks.
# This script attempts to set the maximum allowed regulatory domain power
# for both the jammer (deauth) interface and the access point interface.
# It prefers using 'iw' over 'iwconfig'. Falls back when needed.
# Safe checks prevent invalid or excessive operations.

set -euo pipefail

# Expect environment variables already exported by main fluxion runtime:
#   CaptivePortalJammerInterface
#   CaptivePortalAccessPointInterface
# If not present, we try to infer from running processes (best effort).

err() { echo -e "[power_optimize] ERROR: $*" >&2; }
log() { echo -e "[power_optimize] $*"; }

require_root() {
  if [ $EUID -ne 0 ]; then
    err "Script must run as root."; exit 1
  fi
}

check_tool() { command -v "$1" >/dev/null 2>&1; }

# Determine physical wifi device (phy) for an interface.
iface_phy() {
  local iface="$1"
  if [ -d "/sys/class/net/$iface/phy80211" ]; then
    # Newer kernels often provide a name file.
    if [ -r "/sys/class/net/$iface/phy80211/name" ]; then
      cat "/sys/class/net/$iface/phy80211/name"; return 0
    fi
    # Fallback: resolve via symlink path parsing.
    ls -l "/sys/class/net/$iface/phy80211" | sed 's/^.*\/\([a-zA-Z0-9_-]*\)$/\1/'
    return 0
  fi
  return 1
}

# Get current TX power in dBm using iw (if available)
current_tx_power() {
  local iface="$1"
  if check_tool iw; then
    iw dev "$iface" info 2>/dev/null | awk '/txpower/ {print $2; exit}'
  fi
}

# Attempt to set TX power safely.
# Strategy:
# 1. Query supported frequencies & max power
# 2. Choose highest common value <= 30 (soft cap to avoid illegal values)
# 3. Apply with iw if possible; fallback to iwconfig.
set_tx_power() {
  local iface="$1"
  local phy
  if ! phy=$(iface_phy "$iface"); then
    err "Cannot determine phy for $iface; skipping."; return 1
  fi

  if ! check_tool iw; then
    err "'iw' not available; attempting legacy iwconfig fallback for $iface.";
    if check_tool iwconfig; then
      iwconfig "$iface" txpower 30 2>/dev/null && log "[$iface] Set txpower to 30 dBm (fallback)" || err "[$iface] Failed fallback set"
    fi
    return 0
  fi

  local max_power_list
  max_power_list=$(iw phy "$phy" info 2>/dev/null | awk '/MHz/ && /dBm/ {for(i=1;i<=NF;i++){if($i=="dBm") print $(i-1)}}')
  if [ -z "$max_power_list" ]; then
    err "No power info for phy $phy; skipping $iface."; return 1
  fi

  local chosen=0
  while read -r p; do
    [[ "$p" =~ ^[0-9]+$ ]] || continue
    if [ "$p" -gt "$chosen" ]; then chosen="$p"; fi
  done <<< "$max_power_list"

  # Soft compliance cap (avoid above common regulatory maximum)
  if [ "$chosen" -gt 30 ]; then chosen=30; fi
  if [ "$chosen" -lt 5 ]; then
    err "Computed max power too low ($chosen dBm), skipping $iface."; return 1
  fi

  local before
  before=$(current_tx_power "$iface")
  log "[$iface] Current: ${before:-unknown} dBm | Target: $chosen dBm"

  if iw dev "$iface" set txpower fixed $((chosen * 100)) 2>/dev/null; then
    sleep 0.5
    local after
    after=$(current_tx_power "$iface")
    log "[$iface] Applied: ${after:-$chosen} dBm"
  else
    err "Failed iw set on $iface; attempting iwconfig fallback.";
    if check_tool iwconfig; then
      if iwconfig "$iface" txpower "$chosen" 2>/dev/null; then
        log "[$iface] Applied via iwconfig: $chosen dBm"
      else
        err "Fallback failed for $iface"
      fi
    fi
  fi
}

optimize_all() {
  local changed=0
  for var in CaptivePortalJammerInterface CaptivePortalAccessPointInterface; do
    local iface=${!var:-}
    if [ "$iface" ]; then
      log "Processing $var=$iface"
      set_tx_power "$iface" && changed=1
    else
      log "$var not set; skipping"
    fi
  done
  if [ $changed -eq 0 ]; then
    err "No interfaces optimized. Ensure this runs during an active attack session."
  fi
}

require_root
optimize_all
