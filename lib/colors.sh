#!/usr/bin/env bash
# colors.sh - Color definitions and TTY detection

# shellcheck disable=SC2034  # Variables used by other modules

setup_colors() {
  if [[ -t 1 && -z ${NO_COLOR+x} ]]; then
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    RED='\033[0;31m'
    MAGENTA='\033[0;35m'
    CYAN='\033[0;36m'
    WHITE='\033[1;37m'
    DIM='\033[2m'
    BOLD='\033[1m'
    UNDERLINE='\033[4m'
    NC='\033[0m'

    # ORANGE needs 256-color support; fall back to yellow
    local color_count=8
    if command -v tput >/dev/null 2>&1; then
      color_count="$(tput colors 2>/dev/null || echo 8)"
    fi
    if [[ ! $color_count =~ ^[0-9]+$ ]]; then
      color_count=8
    fi
    if [[ $color_count -ge 256 ]]; then
      ORANGE='\033[38;5;208m'
    else
      ORANGE="$YELLOW"
    fi
  else
    GREEN='' YELLOW='' BLUE='' RED='' MAGENTA='' CYAN='' WHITE=''
    ORANGE='' DIM='' BOLD='' UNDERLINE='' NC=''
  fi
}
