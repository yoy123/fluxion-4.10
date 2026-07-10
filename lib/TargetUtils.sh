#!/usr/bin/env bash

if [ "$TargetUtilsVersion" ]; then return 0; fi
readonly TargetUtilsVersion="1.0"

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

# FLUXSCRIPT END
