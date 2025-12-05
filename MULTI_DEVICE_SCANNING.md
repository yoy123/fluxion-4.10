# Multi-Device Parallel Scanning Feature

## Overview
Fluxion now supports scanning with multiple wireless interfaces simultaneously, significantly improving target discovery speed and coverage.

## How It Works

### 1. **Automatic Detection**
When you start a target scan, Fluxion automatically detects all available wireless interfaces in monitor mode.

### 2. **Scanning Mode Selection**
If multiple interfaces are available, you'll be prompted to choose:
- **Single interface scan**: Traditional scan using one device (original behavior)
- **Multi-interface parallel scan**: Simultaneous scanning across all detected devices

### 3. **Parallel Execution**
When multi-device mode is selected:
- Each interface launches airodump-ng in its own xterm window
- All interfaces scan simultaneously (no waiting between devices)
- Each window shows scan progress for its respective interface

### 4. **Result Merging**
After scanning completes:
- CSV files from all interfaces are automatically merged
- Duplicate access points are removed (keeping the strongest signal)
- Client information is consolidated
- Results are presented in a unified list

## Benefits

### Speed
- **2 devices**: ~2x faster coverage
- **3 devices**: ~3x faster coverage
- **N devices**: ~N× faster coverage

### Coverage
- Different interfaces may detect different APs based on antenna characteristics
- Physical positioning of multiple adapters can improve signal reception
- Band-specific scanning (2.4GHz on one, 5GHz on another)

### Flexibility
- Works with any number of wireless interfaces
- Automatically handles different chipsets
- Falls back to single-device mode if only one interface available

## Usage Example

```bash
# Run fluxion as root
sudo ./fluxion.sh

# Select your attack type
# Choose interface for scanning
# If multiple interfaces detected, select "Multi-interface parallel scan"
# Choose channel/band options as normal
# All devices will scan in parallel automatically
```

## Technical Details

### Interface Detection
- Scans for interfaces matching `*mon*` pattern (monitor mode)
- Checks allocated interfaces in FluxionInterfaces array
- Only includes wireless-capable devices

### File Management
- Each interface writes to `scan_N-01.csv` where N is the interface index
- Temporary files: `merged_aps.tmp` and `merged_clients.tmp`
- All temporary files cleaned up after merge

### Deduplication Algorithm
```bash
# For Access Points:
sort -t, -k1,1 -k9,9nr  # Sort by MAC, then by power (descending)
awk -F, '!seen[$1]++'   # Keep first occurrence (strongest signal)

# For Clients:
sort -t, -k1,1 -u       # Unique by MAC address
```

## Security Improvements
This feature also includes security fixes:
- Randomized workspace directory (no more predictable `/tmp/fluxspace`)
- Fixed eval-based command injection in `io_dynamic_output`
- Proper file permission handling (700 on workspace)

## Requirements
- Multiple wireless interfaces in monitor mode
- Sufficient xterm windows support
- Root privileges (already required for Fluxion)

## Compatibility
- Works with existing Fluxion attacks
- Maintains backward compatibility (single-device mode still available)
- No changes to attack scripts required
