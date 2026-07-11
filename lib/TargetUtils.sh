#!/usr/bin/env bash

if [ "$TargetUtilsVersion" ]; then return 0; fi
readonly TargetUtilsVersion="1.0"

if ! declare -p TargetOUIVendorCache &> /dev/null; then
  declare -A TargetOUIVendorCache=()
fi

# Sort airodump-ng CSV records by descending signal strength. PWR=-1 is unknown.
target_sort_candidates_by_signal() {
  awk -F, '
    NF {
      power = $9
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", power)
      if (power !~ /^-?[0-9]+$/ || power == "-1") {
        power = -1000
      }
      print power "\t" $0
    }
  ' |
    sort -s -t $'\t' -k1,1nr |
    cut -f2-
}

# Look up a globally administered MAC address in macchanger's local OUI database.
target_lookup_oui_vendor() {
  local mac="${1^^}"
  local oui="${mac:0:8}"
  local firstOctet
  local vendor

  TargetOUIVendor=""

  if [[ ! "$oui" =~ ^([0-9A-F]{2}:){2}[0-9A-F]{2}$ ]]; then
    return 1
  fi

  firstOctet=$((16#${oui:0:2}))
  if (( firstOctet & 2 )); then
    return 1
  fi

  if [[ ${TargetOUIVendorCache[$oui]+present} ]]; then
    TargetOUIVendor="${TargetOUIVendorCache[$oui]}"
    [ -n "$TargetOUIVendor" ]
    return
  fi

  vendor=$(macchanger -l 2>/dev/null |
    awk -F ' - ' -v oui="$oui" '$2 == oui { print $3; exit }')
  TargetOUIVendorCache["$oui"]="$vendor"
  TargetOUIVendor="$vendor"
  [ -n "$TargetOUIVendor" ]
}

# Identify manufacturers whose OUI is strongly associated with IoT products.
target_vendor_is_iot() {
  local vendor="${1,,}"

  case "$vendor" in
    *arlo*|*ecobee*|*espressif*|*eufy*|*itead*|*irobot*|*lumi\ united*|\
    *meross*|*netatmo*|*philips\ lighting*|*ring\ llc*|*roborock*|*shelly*|\
    *signify*|*smartthings*|*sonoff*|*tado*|*tuya*|*wyze*)
      return 0 ;;
  esac

  return 1
}

# Populate observed and IoT client counts for a BSSID from airodump station CSV rows.
# The IoT count is a conservative OUI-manufacturer heuristic, not a device inventory.
target_count_observed_clients() {
  local targetBSSID="${1//[[:space:]]/}"
  local stationMAC
  local associatedBSSID
  local -A seenStations=()

  shift
  targetBSSID="${targetBSSID^^}"
  TargetObservedClientCount=0
  TargetIoTClientCount=0

  while IFS=$'\t' read -r stationMAC associatedBSSID; do
    if [ "$associatedBSSID" != "$targetBSSID" ] || \
      [[ ${seenStations[$stationMAC]+present} ]]; then
      continue
    fi

    seenStations["$stationMAC"]=1
    TargetObservedClientCount=$((TargetObservedClientCount + 1))

    if target_lookup_oui_vendor "$stationMAC" && \
      target_vendor_is_iot "$TargetOUIVendor"; then
      TargetIoTClientCount=$((TargetIoTClientCount + 1))
    fi
  done < <(
    printf '%s\n' "$@" |
      awk -F, 'NF >= 6 {
        station = $1
        bssid = $6
        gsub(/[[:space:]]/, "", station)
        gsub(/[[:space:]]/, "", bssid)
        if (station != "" && bssid != "") {
          print toupper(station) "\t" toupper(bssid)
        }
      }'
  )
}

# FLUXSCRIPT END
