#!/usr/bin/env bash

# ============================================================ #
# ================= < WEF Attack Module > ==================== #
# ============================================================ #
# WiFi Exploitation Framework integration with Fluxion
# WEF provides comprehensive WiFi attacks in a single tool

WEFState="Not Ready"

# Path to WEF
readonly WEFPath="$FLUXIONPath/WEF"
readonly WEFBinary="$WEFPath/wef"

# ============================================================ #
# =================== < WEF Header > ========================= #
# ============================================================ #
wef_header() {
  fluxion_header
  echo -e "${CYel}  WiFi Exploitation Framework${CClr}"
  echo
}

# ============================================================ #
# ================= < WEF Subroutines > ====================== #
# ============================================================ #

wef_check_dependencies() {
  # Check if WEF binary exists
  if [ ! -x "$WEFBinary" ]; then
    echo -e "${CRed}WEF not found at $WEFBinary${CClr}"
    echo -e "${CYel}Please clone WEF into the fluxion directory:${CClr}"
    echo "  cd $FLUXIONPath && git clone https://github.com/D3Ext/WEF.git"
    sleep 3
    return 1
  fi

  return 0
}

# ============================================================ #
# ============= < Interface Set/Unset > ====================== #
# ============================================================ #

wef_unset_interface() {
  WEFInterfaceOriginal=""
  if [ ! "$WEFInterface" ]; then return 1; fi
  WEFInterface=""
}

wef_set_interface() {
  if [ "$WEFInterface" ]; then return 0; fi

  if [ ! "$WEFInterfaceOriginal" ]; then
    if ! fluxion_get_interface attack_targetting_interfaces \
      "$WEFInterfaceQuery"; then
      return 1
    fi
    WEFInterfaceOriginal=$FluxionInterfaceSelected
  fi

  WEFInterface=$WEFInterfaceOriginal
  return 0
}

# ============================================================ #
# ================= < Run WEF > ============================== #
# ============================================================ #

wef_run() {
  # Create a startup script
  local startupScript="$FLUXIONWorkspacePath/wef_start.sh"
  cat > "$startupScript" << STARTEOF
#!/bin/bash
echo ""
echo "=============================================="
echo "  WiFi Exploitation Framework (WEF)"
echo "=============================================="
echo "  Interface: $WEFInterface"
echo "=============================================="
echo ""
echo "Starting WEF..."
echo ""
cd '$WEFPath'
sudo ./wef -i '$WEFInterface'
echo ""
echo "WEF finished. Press Enter to close..."
read
STARTEOF
  chmod +x "$startupScript"

  # Run WEF in xterm
  xterm -hold -title "WEF - WiFi Exploitation Framework" \
    -bg "#000000" -fg "#00FF00" \
    -geometry 120x40 \
    -e "$startupScript" &
  WEFXtermPID=$!
}

# ============================================================ #
# =================== < Fluxion Hooks > ====================== #
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
  WEFState="Not Ready"
  wef_unset_interface
}

prep_attack() {
  # Check dependencies first
  if ! wef_check_dependencies; then
    return 1
  fi

  IOUtilsHeader="wef_header"

  local sequence=(
    "set_interface"
  )

  if ! fluxion_do_sequence wef sequence[@]; then
    return 1
  fi

  WEFState="Ready"
  return 0
}

start_attack() {
  if [ "$WEFState" = "Running" ]; then return 0; fi
  if [ "$WEFState" != "Ready" ]; then return 1; fi

  WEFState="Running"

  # Run WEF
  wef_run
}

stop_attack() {
  if [ "$WEFXtermPID" ]; then
    kill $WEFXtermPID &> /dev/null 2>&1
    WEFXtermPID=""
  fi

  WEFState="Stopped"
}

# ============================================================ #
# ================ < Language Strings > ====================== #
# ============================================================ #

WEFInterfaceQuery="Select interface for WEF"

# FLUXSCRIPT END
