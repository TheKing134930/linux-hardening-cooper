#!/usr/bin/env bash
set -euo pipefail

invoke_defensive_countermeasures () {
  echo -e "${CYAN}[Defensive Countermeasures] Start${NC}"

  dcm_ufw_reset_factory
  dcm_ufw_enable_and_boot
  dcm_ufw_loopback_policy
  dcm_ufw_deny_ping
  dcm_ufw_allow_ssh

  echo -e "${CYAN}[Defensive Countermeasures] Done${NC}"
}

# ------------------------------------------------------------
# UFW: reset to factory defaults (non-interactive)
# ------------------------------------------------------------
dcm_ufw_reset_factory () {
  : <<'AI_BLOCK'
EXPLANATION
Reset UFW to factory settings without prompting.

AI_PROMPT
Return only Bash code (no markdown, no prose).
Requirements:
- Run the UFW reset command in forced/non-interactive mode.
- Print a short confirmation when complete.
AI_BLOCK
ufw --force reset && echo "UFW reset complete" || echo "Warning: UFW reset failed"

}

# ------------------------------------------------------------
# UFW: ensure enabled now and on boot
# ------------------------------------------------------------
dcm_ufw_enable_and_boot () {
  : <<'AI_BLOCK'
EXPLANATION
Enable the firewall immediately and ensure it starts on boot via systemd.

AI_PROMPT
Return only Bash code (no markdown, no prose).
Requirements:
- Enable UFW (if already enabled, do nothing harmful).
- Enable the ufw systemd unit for boot.
- Print concise status lines for both actions.
AI_BLOCK
ufw enable >/dev/null 2>&1 && echo "UFW enabled" || echo "UFW already enabled or failed"

systemctl enable ufw >/dev/null 2>&1 && echo "UFW systemd unit enabled" || echo "UFW systemd unit already enabled or failed"
}

# ------------------------------------------------------------
# UFW: loopback policy (allow lo in/out, deny spoofed loopback)
# ------------------------------------------------------------
dcm_ufw_loopback_policy () {
  : <<'AI_BLOCK'
EXPLANATION
Set loopback rules:
- Allow inbound and outbound on interface lo.
- Deny inbound traffic claiming to be from 127.0.0.0/8 and from ::1.

AI_PROMPT
Return only Bash code (no markdown, no prose).
Requirements:
- Add UFW rules to allow in on lo and allow out on lo.
- Add UFW rules to deny in from 127.0.0.0/8 and from ::1.
- Print confirmations for each rule.
AI_BLOCK
# Enable UFW firewall and suppress output
ufw enable >/dev/null 2>&1 && echo "UFW enabled" || echo "UFW already enabled or failed"

# Enable UFW systemd unit to start on boot and suppress output
systemctl enable ufw >/dev/null 2>&1 && echo "UFW systemd unit enabled" || echo "UFW systemd unit already enabled or failed"

}

# ------------------------------------------------------------
# UFW: deny ICMP echo-request (ping) responses
# ------------------------------------------------------------
dcm_ufw_deny_ping () {
  : <<'AI_BLOCK'
EXPLANATION
Configure UFW to drop inbound ICMP echo-request (ping) for both IPv4 and IPv6.
Use the recommended UFW approach by editing before.rules/before6.rules so the drop occurs
before default ICMP accepts. Reload UFW afterward.

AI_PROMPT
Return only Bash code (no markdown, no prose).
Requirements:
- Create timestamped backups of:
  - /etc/ufw/before.rules
  - /etc/ufw/before6.rules
- In before.rules, ensure a rule exists to drop ICMP echo-request in the ufw-before-input chain
  (placed before generic ICMP accept rules).
- In before6.rules, ensure a rule exists to drop IPv6 ICMP echo-request similarly.
- Make edits idempotent (do not insert duplicates on subsequent runs).
- Reload UFW to apply changes and print a confirmation.
- Include brief comments in the inserted blocks so students can find them later.
AI_BLOCK
#!/bin/bash

backup_dir="/etc/ufw/backups"
timestamp=$(date +"%Y%m%d%H%M%S")
mkdir -p "$backup_dir"
cp /etc/ufw/before.rules "$backup_dir/before.rules.$timestamp"
cp /etc/ufw/before6.rules "$backup_dir/before6.rules.$timestamp"

insert_icmp_rule() {
  local file=$1
  local icmp_rule=$2
  local chain=$3
  local comment_start="# STUDENT_ICMP_BLOCK_START"
  local comment_end="# STUDENT_ICMP_BLOCK_END"

  # Check if block already exists
  if grep -q "$comment_start" "$file"; then
    return 0
  fi

  # Find line number of generic ICMP accept rule in chain
  local line_num
  line_num=$(awk -v chain="$chain" -v rule="ACCEPT.*icmp" '
    $0 ~ chain {in_chain=1}
    in_chain && $0 ~ rule {print NR; exit}
  ' "$file")

  # If no generic accept found, append at end of chain
  if [ -z "$line_num" ]; then
    line_num=$(grep -n "\[$chain\]" "$file" | cut -d: -f1)
    if [ -z "$line_num" ]; then
      echo "Chain $chain not found in $file"
      return 1
    fi
    line_num=$((line_num + 1))
  fi

  # Prepare block with comment
  local block="$comment_start
-A $chain -p icmp --icmp-type echo-request -j DROP  # Drop ICMP echo-request (ping) - STUDENT BLOCK
$comment_end"

  # Insert block before generic accept rule line
  sed -i "${line_num}i\\
$block
" "$file"
}

insert_icmp_rule /etc/ufw/before.rules "-p icmp --icmp-type echo-request" "ufw-before-input"
insert_icmp_rule /etc/ufw/before6.rules "-p ipv6-icmp --icmpv6-type echo-request" "ufw6-before-input"

ufw reload >/dev/null 2>&1 && echo "UFW reloaded with updated ICMP rules"

}

# ------------------------------------------------------------
# UFW: allow SSH
# ------------------------------------------------------------
dcm_ufw_allow_ssh () {
  : <<'AI_BLOCK'
EXPLANATION
Allow SSH through the firewall using the standard UFW application profile.

AI_PROMPT
Return only Bash code (no markdown, no prose).
Requirements:
- Add a rule to allow SSH (use the named profile, not a hardcoded port).
- Print a short confirmation of the rule addition.
AI_BLOCK
ufw allow OpenSSH >/dev/null 2>&1 && echo "UFW rule added: allow OpenSSH" || echo "Failed to add UFW OpenSSH rule or it already exists"

}
