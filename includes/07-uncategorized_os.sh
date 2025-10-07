#!/usr/bin/env bash
set -euo pipefail

invoke_uncategorized_os () {
  echo -e "${CYAN}[Uncategorized OS] Start${NC}"

  uos_home_dir_permissions
  uos_login_defs_permissions
  uos_shadow_gshadow_permissions
  uos_passwd_group_permissions
  uos_grub_permissions
  uos_system_map_permissions
  uos_ssh_host_keys_permissions
  uos_audit_rules_permissions
  uos_remove_world_writable_files
  uos_report_unowned_files
  uos_var_log_permissions
  uos_tmp_permissions

  # (Any additional one-offs can be added above)
  echo -e "${CYAN}[Uncategorized OS] Done${NC}"
}

# -------------------------------------------------------------------
# Home directories: 0700 perms
# -------------------------------------------------------------------
uos_home_dir_permissions () {
  : <<'AI_BLOCK'
EXPLANATION
Set each first-level directory under /home to mode 0700.

AI_PROMPT
Return only Bash code (no markdown, no prose).
Requirements:
- Find directories at depth 1 under /home.
- For each, chmod 700; print a short confirmation per directory.
- Continue on errors; do not abort the loop.
AI_BLOCK
find /home -mindepth 1 -maxdepth 1 -type d | while read -r dir; do
  if chmod 700 "$dir"; then
    echo "Set permissions 700 on $dir"
  else
    echo "Failed to set permissions on $dir"
  fi
done

}

# -------------------------------------------------------------------
# /etc/login.defs: 0600 root:root
# -------------------------------------------------------------------
uos_login_defs_permissions () {
  : <<'AI_BLOCK'
EXPLANATION
Ensure /etc/login.defs ownership and permissions are strict.

AI_PROMPT
Return only Bash code (no markdown, no prose).
Requirements:
- chown root:root /etc/login.defs
- chmod 0600 /etc/login.defs
- Print a concise confirmation.
AI_BLOCK
chown root:root /etc/login.defs && chmod 0600 /etc/login.defs && echo "/etc/login.defs ownership and permissions set"

}

# -------------------------------------------------------------------
# shadow/gshadow and backups: 0640 root:shadow
# -------------------------------------------------------------------
uos_shadow_gshadow_permissions () {
  : <<'AI_BLOCK'
EXPLANATION
Set ownership/permissions on sensitive account DB files and their backups:
  /etc/shadow     -> root:shadow 0640
  /etc/shadow-    -> root:shadow 0640
  /etc/gshadow    -> root:shadow 0640
  /etc/gshadow-   -> root:shadow 0640

AI_PROMPT
Return only Bash code (no markdown, no prose).
Requirements:
- For each listed file that exists:
  - chown root:shadow
  - chmod 0640
  - Print a confirmation per file; skip cleanly if missing.
AI_BLOCK
files=(
  /etc/shadow
  /etc/gshadow
  /etc/security/opasswd
)

for file in "${files[@]}"; do
  if [ -e "$file" ]; then
    chown root:shadow "$file" && chmod 0640 "$file" && echo "Set owner and permissions on $file"
  else
    echo "Skipping missing file: $file"
  fi
done

}

# -------------------------------------------------------------------
# passwd/group and backups: 0644 root:root
# -------------------------------------------------------------------
uos_passwd_group_permissions () {
  : <<'AI_BLOCK'
EXPLANATION
Set ownership/permissions on:
  /etc/passwd   -> root:root 0644
  /etc/passwd-  -> root:root 0644
  /etc/group    -> root:root 0644
  /etc/group-   -> root:root 0644

AI_PROMPT
Return only Bash code (no markdown, no prose).
Requirements:
- For each existing file above:
  - chown root:root
  - chmod 0644
  - Print a confirmation per file; skip missing files without error.
AI_BLOCK
#!/bin/bash

files=(
  /etc/shadow
  /etc/gshadow
  /etc/security/opasswd
)

for file in "${files[@]}"; do
  if [ -e "$file" ]; then
    chown root:root "$file" && chmod 0644 "$file" && echo "Set owner root:root and permissions 644 on $file"
  fi
done
}


# -------------------------------------------------------------------
# GRUB config: 0600 root:root
# -------------------------------------------------------------------
uos_grub_permissions () {
  : <<'AI_BLOCK'
EXPLANATION
Lock down /boot/grub/grub.cfg.

AI_PROMPT
Return only Bash code (no markdown, no prose).
Requirements:
- If /boot/grub/grub.cfg exists:
  - chown root:root
  - chmod 0600
  - Print a confirmation.
- If missing, print a brief note and continue.
AI_BLOCK
file="/boot/grub/grub.cfg"

if [ -e "$file" ]; then
  chown root:root "$file" && chmod 0600 "$file" && echo "Set owner root:root and permissions 600 on $file"
else
  echo "$file not found, skipping"
fi

}

# -------------------------------------------------------------------
# System.map (if present): 0600 root:root
# -------------------------------------------------------------------
uos_system_map_permissions () {
  : <<'AI_BLOCK'
EXPLANATION
Restrict any /boot/System.map-* files so only root can read/write.

AI_PROMPT
Return only Bash code (no markdown, no prose).
Requirements:
- For each path matching /boot/System.map-* that exists and is a regular file:
  - chown root:root
  - chmod 0600
  - Print a confirmation per file.
- Continue on errors for individual files.
AI_BLOCK
for file in /boot/System.map-*; do
  if [ -f "$file" ]; then
    chown root:root "$file" && chmod 0600 "$file" && echo "Set owner root:root and permissions 600 on $file" || echo "Failed on $file"
  fi
done

}

# -------------------------------------------------------------------
# SSH host keys: 0600 (at least RSA & ECDSA)
# -------------------------------------------------------------------
uos_ssh_host_keys_permissions () {
  : <<'AI_BLOCK'
EXPLANATION
Ensure SSH host private keys are not world/group-readable. At minimum:
  /etc/ssh/ssh_host_rsa_key
  /etc/ssh/ssh_host_ecdsa_key

AI_PROMPT
Return only Bash code (no markdown, no prose).
Requirements:
- For each listed file that exists:
  - chmod 0600
  - Print a confirmation per file; skip missing without error.
AI_BLOCK
files=(
  /etc/shadow
  /etc/gshadow
  /etc/security/opasswd
)

for file in "${files[@]}"; do
  if [ -e "$file" ]; then
    chmod 0600 "$file" && echo "Set permissions 600 on $file"
  fi
done

}

# -------------------------------------------------------------------
# Audit rules: remove dangerous bits on /etc/audit/rules.d/*.rules
# -------------------------------------------------------------------
uos_audit_rules_permissions () {
  : <<'AI_BLOCK'
EXPLANATION
Normalize permissions on files under /etc/audit/rules.d/ ending with .rules:
- Remove setuid/setgid/sticky and group/world write/execute where present.

AI_PROMPT
Return only Bash code (no markdown, no prose).
Requirements:
- Find regular files in /etc/audit/rules.d/ with names ending in .rules (maxdepth 1).
- For each, strip u+s, g+ws, o+wrx (i.e., ensure tight perms) using chmod.
- Print a confirmation per file; continue on errors.
AI_BLOCK
find /etc/audit/rules.d/ -maxdepth 1 -type f -name '*.rules' | while read -r file; do
  if chmod u-s,g-ws,o-wrx "$file"; then
    echo "Permissions tightened on $file"
  else
    echo "Failed to set permissions on $file"
  fi
done

}

# -------------------------------------------------------------------
# Remove world-writable files (clear o+w) on local filesystems
# -------------------------------------------------------------------
uos_remove_world_writable_files () {
  : <<'AI_BLOCK'
EXPLANATION
Find world-writable regular files on local filesystems and remove the world-write bit.

AI_PROMPT
Return only Bash code (no markdown, no prose).
Requirements:
- Enumerate local mount points (df --local -P) and scan each with find.
- Match regular files with world-write permission.
- For each match, chmod o-w; print a confirmation per file.
- Continue on errors; avoid descending into other filesystems (-xdev).
AI_BLOCK
df --local -P | tail -n +2 | awk '{print $6}' | while read -r mountpoint; do
  find "$mountpoint" -xdev -type f -perm -o=w 2>/dev/null | while read -r file; do
    if chmod o-w "$file"; then
      echo "Removed world-write permission from $file"
    else
      echo "Failed to modify $file"
    fi
  done
done

}

# -------------------------------------------------------------------
# Report files without user/group ownership (no destructive fix)
# -------------------------------------------------------------------
uos_report_unowned_files () {
  : <<'AI_BLOCK'
EXPLANATION
Detect files that have no valid user or group ownership on local filesystems and write a report to $DOCS.

AI_PROMPT
Return only Bash code (no markdown, no prose).
Requirements:
- Ensure $DOCS exists (create if needed).
- For each local mount (df --local -P):
  - List paths with -nouser or -nogroup using find -xdev.
- Write results to $DOCS/unowned_files.txt (overwrite).
- Print the number of findings and the report path.
AI_BLOCK
mkdir -p "$DOCS"
output="$DOCS/unowned_files.txt"
> "$output"

df --local -P | tail -n +2 | awk '{print $6}' | while read -r mountpoint; do
  find "$mountpoint" -xdev \( -nouser -o -nogroup \) 2>/dev/null >> "$output"
done

count=$(wc -l < "$output")
echo "$count unowned files found. Report saved to $output"

}

# -------------------------------------------------------------------
# Normalize /var/log permissions to 0640 for files
# -------------------------------------------------------------------
uos_var_log_permissions () {
  : <<'AI_BLOCK'
EXPLANATION
Set permissions of regular files under /var/log to 0640.

AI_PROMPT
Return only Bash code (no markdown, no prose).
Requirements:
- Traverse /var/log (recursive).
- For each regular file, chmod 0640.
- Continue on errors; print a brief summary or per-file confirmations.
AI_BLOCK
count=0
errors=0

find /var/log -type f 2>/dev/null | while read -r file; do
  if chmod 0640 "$file"; then
    echo "Set permissions 640 on $file"
    ((count++))
  else
    echo "Failed to set permissions on $file"
    ((errors++))
  fi
done

echo "Processed $count files with $errors errors."

}

# -------------------------------------------------------------------
# /tmp and /var/tmp: 1777 root:root
# -------------------------------------------------------------------
uos_tmp_permissions () {
  : <<'AI_BLOCK'
EXPLANATION
Ensure /tmp and /var/tmp are sticky world-writable directories owned by root (1777 root:root).

AI_PROMPT
Return only Bash code (no markdown, no prose).
Requirements:
- For /tmp and /var/tmp:
  - chown root:root
  - chmod 1777
  - Print a confirmation per directory.
AI_BLOCK
for dir in /tmp /var/tmp; do
  if chown root:root "$dir" && chmod 1777 "$dir"; then
    echo "Set ownership root:root and permissions 1777 on $dir"
  else
    echo "Failed to set ownership or permissions on $dir"
  fi
done

}
