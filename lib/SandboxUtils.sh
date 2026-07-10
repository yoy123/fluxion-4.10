#!/usr/bin/env bash

if [ "$SandboxUtilsVersion" ]; then return 0; fi
readonly SandboxUtilsVersion="1.0"

SandboxWorkspacePath="/tmp/sandbox"
SandboxOutputDevice="/dev/stdout"

# After changing global identifiers in the main script,
# I forgot to update the identifiers here, leading to a
# horrific accident where the script ended and executed
# the command "rm -rf /*" ... yeah, fuck that...
# Spent an entire day retreiving all my shit back.
function sandbox_remove_workfile() {
  local targetPattern="${1:-}"
  local outputDevice="${SandboxOutputDevice:-/dev/stderr}"
  local workspacePath
  local target
  local targetPath
  local targets=()

  # Check we've got the environment variables ready.
  if [[ -z "$SandboxWorkspacePath" || -z "$SandboxOutputDevice" ]]; then
    echo "The workspace path, or the output device is missing." > "$outputDevice"
    return 1
  fi

  workspacePath=$(readlink -m -- "$SandboxWorkspacePath")
  targetPath=$(readlink -m -- "$targetPattern")

  # Check the pattern itself is bounded by the workspace directory.
  if [[ -z "$targetPattern" || "$targetPath" != "$workspacePath/"* ]]; then
    echo "Stopped an attempt to delete non-workfiles." > "$outputDevice"
    return 2
  fi

  if [[ -e "$targetPattern" || -L "$targetPattern" ]]; then
    targets=("$targetPattern")
  else
    mapfile -t targets < <(compgen -G "$targetPattern")
  fi

  # A cleanup request with no matches is already complete.
  if (( ${#targets[@]} == 0 )); then
    return 0
  fi

  # Recheck expanded paths so traversal through a glob or symlink is rejected.
  for target in "${targets[@]}"; do
    targetPath=$(readlink -m -- "$target")
    if [[ "$targetPath" != "$workspacePath/"* ]]; then
      echo "Stopped an attempt to delete non-workfiles." > "$outputDevice"
      return 2
    fi
  done

  # Remove the target file (do NOT force it).
  rm -r -- "${targets[@]}" &> "$outputDevice"
}

# FLUXSCRIPT END
