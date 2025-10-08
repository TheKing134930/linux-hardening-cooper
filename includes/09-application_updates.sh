#!/usr/bin/env bash
set -euo pipefail

invoke_application_updates () {
  echo -e "${CYAN}[Application Updates] Start${NC}"

  au_apt_update_indexes
  au_apt_full_upgrade
  au_snap_refresh_all
  au_flatpak_update_all

  echo -e "${CYAN}[Application Updates] Done${NC}"
}

# ------------------------------------------------------------
# apt: update package indexes
# ------------------------------------------------------------
au_apt_update_indexes () {
  # Print a short status message
  echo "Updating APT indexes..."

  # Run apt update quietly; keep output concise. Capture exit code but do not exit on failure.
  if ! sudo apt update -qq; then
    echo "Warning: APT index update failed (continuing)."
  fi

  echo "APT index update complete."
}

# ------------------------------------------------------------
# apt: full upgrade (non-interactive)
# ------------------------------------------------------------
au_apt_full_upgrade () {
  echo "Running APT full upgrade..."

  # Perform a full upgrade non-interactively; keep output concise. Do not exit on failure.
  if ! sudo DEBIAN_FRONTEND=noninteractive apt full-upgrade -y -qq; then
    echo "Warning: APT full upgrade failed (continuing)."
  fi

  echo "APT full upgrade complete."
}

# ------------------------------------------------------------
# snap: refresh all snaps (if snap is installed)
# ------------------------------------------------------------
au_snap_refresh_all () {
  # Check if snap is available
  if ! command -v snap >/dev/null 2>&1; then
    echo "Snap not installed; skipping."
    return
  fi

  echo "Refreshing Snap packages..."

  # Refresh all snaps; keep output concise and don't exit on failure
  if ! sudo snap refresh --list >/dev/null 2>&1 || ! sudo snap refresh >/dev/null 2>&1; then
    echo "Warning: Snap refresh encountered an issue (continuing)."
  fi

  echo "Snap refresh complete."
}

# ------------------------------------------------------------
# flatpak: update all (if flatpak is installed)
# ------------------------------------------------------------
au_flatpak_update_all () {
  # Check if flatpak is available
  if ! command -v flatpak >/dev/null 2>&1; then
    echo "Flatpak not installed; skipping."
    return
  fi

  echo "Updating Flatpak apps/runtimes..."

  # Update flatpak apps and runtimes non-interactively; do not exit on failure
  if ! flatpak update -y >/dev/null 2>&1; then
    echo "Warning: Flatpak update encountered an issue (continuing)."
  fi

  echo "Flatpak update complete."
}
