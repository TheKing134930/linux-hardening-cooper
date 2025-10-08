#!/usr/bin/env bash
set -euo pipefail

invoke_unwanted_software () {
  echo -e "${CYAN}[Unwanted Software] Start${NC}"

  us_purge_unwanted_software

  echo -e "${CYAN}[Unwanted Software] Done${NC}"
}

# -------------------------------------------------------------------
# Purge unwanted software listed in $UNWANTED_SOFTWARE, then autoremove
# -------------------------------------------------------------------
us_purge_unwanted_software () {
  # Support UNWANTED_SOFTWARE being unset, an empty string, a space-separated string, or a Bash array
  if [ -z "${UNWANTED_SOFTWARE+x}" ]; then
    echo "No unwanted software configured."
    return
  fi

  # Build an array of package names
  local pkgs=()
  if [ "$(declare -p UNWANTED_SOFTWARE 2>/dev/null || true)" ] && [[ $(declare -p UNWANTED_SOFTWARE 2>/dev/null) =~ "declare -a" ]]; then
    # It's an array
    pkgs=("${UNWANTED_SOFTWARE[@]}")
  else
    # Treat as a whitespace-separated string
    read -r -a pkgs <<< "${UNWANTED_SOFTWARE}"
  fi

  local name
  for name in "${pkgs[@]}"; do
    name="$(echo "$name" | xargs)"
    [ -z "$name" ] && continue

    echo "Purging unwanted package: ${name}..."

    # Use apt purge with wildcard matching for packages that may have suffixes
    if sudo DEBIAN_FRONTEND=noninteractive apt purge -y -qq "${name}*" >/dev/null 2>&1; then
      echo "Purged: ${name}"
    else
      echo "Warning: purge failed for ${name}, attempting to recover..."
      # Attempt to fix dpkg state then retry once
      sudo dpkg --configure -a >/dev/null 2>&1 || true
      if sudo DEBIAN_FRONTEND=noninteractive apt purge -y -qq "${name}*" >/dev/null 2>&1; then
        echo "Purged on retry: ${name}"
      else
        echo "Warning: final purge failed for ${name}"
      fi
    fi
  done

  # Autoremove unused dependencies quietly
  if sudo DEBIAN_FRONTEND=noninteractive apt autoremove -y -qq >/dev/null 2>&1; then
    echo "Autoremove complete."
  else
    echo "Warning: apt autoremove failed (continuing)."
  fi
}
