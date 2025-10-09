#!/usr/bin/env bash
set -euo pipefail

invoke_local_policy () {
  echo -e "${CYAN}[Local Policy] Start${NC}"

  lp_sysctl_ipv6_all
  lp_sysctl_ipv6_default
  lp_sysctl_ipv4_all
  lp_sysctl_ipv4_default
  lp_sysctl_ipv4_misc
  lp_sysctl_fs_kernel
  lp_sysctl_persist_and_reload
  lp_secure_sudo

  echo -e "${CYAN}[Local Policy] Done${NC}"
}

# -------------------------------------------------------------------
# IPv6 sysctl (all interfaces)
# -------------------------------------------------------------------
lp_sysctl_ipv6_all () {
  : <<'AI_BLOCK'
EXPLANATION
Set these IPv6 values (applies to all interfaces):
  net.ipv6.conf.all.accept_ra=0
  net.ipv6.conf.all.accept_redirects=0
  net.ipv6.conf.all.accept_source_route=0
  net.ipv6.conf.all.forwarding=0

AI_PROMPT
Return only Bash code (no markdown, no prose).
Requirements:
- Apply the runtime changes with the appropriate sysctl command.
- Print a short confirmation per key.
- Continue on errors; do not abort the script if one key fails.
AI_BLOCK
declare -A sysctl_keys=(
[net.ipv4.ip_forward]=1
[vm.swappiness]=10
[kernel.pid_max]=65536
)

for key in "${!sysctl_keys[@]}"; do
if sysctl -w "$key=${sysctl_keys[$key]}" 2>/dev/null; then
echo "$key set to ${sysctl_keys[$key]}"
else
echo "Failed to set $key"
fi
done
}

# -------------------------------------------------------------------
# IPv6 sysctl (default interface template)
# -------------------------------------------------------------------
lp_sysctl_ipv6_default () {
  : <<'AI_BLOCK'
EXPLANATION
Set these IPv6 default-interface values:
  net.ipv6.conf.default.accept_ra=0
  net.ipv6.conf.default.accept_redirects=0
  net.ipv6.conf.default.accept_source_route=0

AI_PROMPT
Return only Bash code (no markdown, no prose).
Requirements:
- Apply the runtime changes with sysctl.
- Print a short confirmation per key.
- Continue on errors.
AI_BLOCK
declare -A sysctl_keys=(
[net.ipv4.ip_forward]=1
[vm.swappiness]=10
[kernel.pid_max]=65536
)

for key in "${!sysctl_keys[@]}"; do
sysctl -w "$key=${sysctl_keys[$key]}" >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
echo "$key set to ${sysctl_keys[$key]}"
else
echo "Failed to set $key"
fi
done
}

# -------------------------------------------------------------------
# IPv4 sysctl (all interfaces)
# -------------------------------------------------------------------
lp_sysctl_ipv4_all () {
  : <<'AI_BLOCK'
EXPLANATION
Set these IPv4 values (all interfaces):
  net.ipv4.conf.all.accept_redirects=0
  net.ipv4.conf.all.accept_source_route=0
  net.ipv4.conf.all.log_martians=1
  net.ipv4.conf.all.rp_filter=1
  net.ipv4.conf.all.secure_redirects=0
  net.ipv4.conf.all.send_redirects=0

AI_PROMPT
Return only Bash code (no markdown, no prose).
Requirements:
- Apply runtime changes with sysctl.
- Print a short confirmation per key.
- Continue on errors.
AI_BLOCK
sysctl_keys=(
"net.ipv4.ip_forward=1"
"vm.swappiness=10"
"kernel.pid_max=65536"
)

for entry in "${sysctl_keys[@]}"; do
if sysctl -w "$entry" >/dev/null 2>&1; then
key="${entry%%=}"
value="${entry#=}"
echo "$key set to $value"
else
key="${entry%%=*}"
echo "Failed to set $key"
fi
done
}

# -------------------------------------------------------------------
# IPv4 sysctl (default interface template)
# -------------------------------------------------------------------
lp_sysctl_ipv4_default () {
  : <<'AI_BLOCK'
EXPLANATION
Set these IPv4 default-interface values:
  net.ipv4.conf.default.accept_redirects=0
  net.ipv4.conf.default.accept_source_route=0
  net.ipv4.conf.default.log_martians=1
  net.ipv4.conf.default.rp_filter=1
  net.ipv4.conf.default.secure_redirects=0
  net.ipv4.conf.default.send_redirects=0

AI_PROMPT
Return only Bash code (no markdown, no prose).
Requirements:
- Apply runtime changes with sysctl.
- Print a short confirmation per key.
- Continue on errors.
AI_BLOCK
for key in net.ipv4.ip_forward vm.swappiness kernel.pid_max; do
case "$key" in
net.ipv4.ip_forward) value=1 ;;
vm.swappiness) value=10 ;;
kernel.pid_max) value=65536 ;;
esac
if sysctl -w "$key=$value" >/dev/null 2>&1; then
echo "$key set to $value"
else
echo "Failed to set $key"
fi
done
}

# -------------------------------------------------------------------
# IPv4 misc (ICMP, TCP, forwarding)
# -------------------------------------------------------------------
lp_sysctl_ipv4_misc () {
  : <<'AI_BLOCK'
EXPLANATION
Set these additional IPv4 values:
  net.ipv4.icmp_echo_ignore_broadcasts=1
  net.ipv4.icmp_ignore_bogus_error_responses=1
  net.ipv4.tcp_syncookies=1
  net.ipv4.ip_forward=0

AI_PROMPT
Return only Bash code (no markdown, no prose).
Requirements:
- Apply runtime changes with sysctl.
- Print a short confirmation per key.
- Continue on errors.
AI_BLOCK
for key in net.ipv4.icmp_echo_ignore_broadcasts=1 net.ipv4.icmp_ignore_bogus_error_responses=1 net.ipv4.tcp_syncookies=1 net.ipv4.ip_forward=0; do
  sudo sysctl -w "$key" && echo "Set $key" || echo "Failed to set $key"
done

}

# -------------------------------------------------------------------
# Filesystem & kernel hardening
# -------------------------------------------------------------------
lp_sysctl_fs_kernel () {
  : <<'AI_BLOCK'
EXPLANATION
Set these filesystem/kernel hardening values:
  fs.protected_hardlinks=1
  fs.protected_symlinks=1
  fs.suid_dumpable=0
  kernel.randomize_va_space=2

AI_PROMPT
Return only Bash code (no markdown, no prose).
Requirements:
- Apply runtime changes with sysctl.
- Print a short confirmation per key.
- Continue on errors.
AI_BLOCK
#!/usr/bin/env bash
set -u

apply_sysctl() {
local key="$1" desired="$2"
if ! command -v sysctl >/dev/null 2>&1; then
echo "[ERR] $key -> sysctl not found"
return 0
fi

if sysctl -w "${key}=${desired}" >/dev/null 2>&1; then
local current
current="$(sysctl -n "${key}" 2>/dev/null || echo "?")"
if [[ "${current}" == "${desired}" ]]; then
echo "[OK] ${key}=${current}"
else
echo "[WARN] ${key} applied, readback=${current}, expected=${desired}"
fi
else
echo "[ERR] ${key} -> failed to apply"
fi
}

apply_sysctl "fs.protected_hardlinks" "1"
apply_sysctl "fs.protected_symlinks" "1"
apply_sysctl "fs.suid_dumpable" "0"
apply_sysctl "kernel.randomize_va_space" "2"

}

# -------------------------------------------------------------------
# Persist sysctl settings and reload
# -------------------------------------------------------------------
lp_sysctl_persist_and_reload () {
  : <<'AI_BLOCK'
EXPLANATION
Persist all the above sysctl settings and reload them immediately.

AI_PROMPT
Return only Bash code (no markdown, no prose).
Requirements:
- Write all earlier keys and values into a single file under /etc/sysctl.d/, e.g., /etc/sysctl.d/99-hardening.conf.
- Create a timestamped backup if that file already exists.
- Ensure each key=value appears exactly once (idempotent write).
- Reload settings with sysctl so they take effect without reboot (e.g., sysctl --system).
- Print a summary of the file written and reload status.
AI_BLOCK
outfile="/etc/sysctl.d/99-hardening.conf"
[[ -f "$outfile" ]] && cp "$outfile" "${outfile}.$(date +%Y%m%d%H%M%S).bak"

declare -A settings=(
[net.ipv4.ip_forward]=1
[vm.swappiness]=10
[kernel.pid_max]=65536
[net.ipv4.conf.all.rp_filter]=1
[net.ipv4.conf.default.rp_filter]=1
[net.ipv4.icmp_echo_ignore_broadcasts]=1
[net.ipv4.icmp_ignore_bogus_error_responses]=1
)

tmpfile=$(mktemp)
for key in "${!settings[@]}"; do
echo "$key=${settings[$key]}" >> "$tmpfile"
done

sort -u "$tmpfile" > "$outfile"
rm -f "$tmpfile"

if sysctl --system >/dev/null 2>&1; then
echo "Wrote $outfile and applied settings"
else
echo "Wrote $outfile but failed to apply settings"
fi
}

# -------------------------------------------------------------------
# Secure sudo (dangerous if misused; stub only)
# -------------------------------------------------------------------
lp_secure_sudo () {
  : <<'AI_BLOCK'
EXPLANATION
Harden sudo configuration by clearing drop-ins and reinstalling sudo (Debian/Ubuntu/Mint).
This is destructive; students should understand risks and test in a VM.

AI_PROMPT
Return only Bash code (no markdown, no prose).
Requirements:
- Remove all files under /etc/sudoers.d/ (do not delete /etc/sudoers).
- Purge the sudo package non-interactively.
- Install sudo again non-interactively.
- Print confirmation lines for each step.
- Continue on errors with a warning, but attempt subsequent steps.
AI_BLOCK
find /etc/sudoers.d/ -type f -exec rm -f {}  && echo "Removed files in /etc/sudoers.d" || echo "Warning: Failed to remove some files in /etc/sudoers.d"

DEBIAN_FRONTEND=noninteractive apt-get purge -y sudo && echo "Purged sudo" || echo "Warning: Failed to purge sudo"

DEBIAN_FRONTEND=noninteractive apt-get install -y sudo && echo "Reinstalled sudo" || echo "Warning: Failed to install sudo"
}
