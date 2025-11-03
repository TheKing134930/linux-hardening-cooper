#!/usr/bin/env bash
set -euo pipefail

invoke_account_policy () {
  echo -e "${CYAN}[Account Policy] Start${NC}"

  ap_secure_login_defs
  ap_blankpasswords_disallow
  ap_pam_pwquality_inline
  ap_pwquality_conf_file
  #ap_lockout_faillock

  echo -e "${CYAN}[Account Policy] Done${NC}"
}

# -------------------------------------------------------------------
# /etc/login.defs hardening
# -------------------------------------------------------------------

ap_secure_login_defs () {
  sudo sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS\t60/g' /etc/login.defs
  sudo sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS\t10/g' /etc/login.defs
  sudo sed -i 's/^PASS_WARN_AGE.*/PASS_WARN_AGE\t14/g' /etc/login.defs
  sudo sed -i 's/^UMASK.*/UMASK\t077/g' /etc/login.defs
}

ap_blankpasswords_disallow () {
sed -i '/pam_unix.so/s/nullok[_secure]*//g' /etc/pam.d/common-auth
}

# -------------------------------------------------------------------
# Insert pam_pwquality inline in common-password
# -------------------------------------------------------------------
ap_pam_pwquality_inline () {
backup="/etc/pam.d/common-password.$(date +%Y%m%d%H%M%S).bak"
file="/etc/pam.d/common-password"
line="password requisite pam_pwquality.so retry=3"

cp "$file" "$backup"

if ! grep -Fxq "$line" "$file"; then
awk -v insert="$line" '
{if(!inserted && $0 ~ /pam_unix.so/) {print insert; inserted=1} print}
' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
fi

grep -Fxq "$line" "$file" && echo "pwquality line is in place."
}

# -------------------------------------------------------------------
# Configure /etc/security/pwquality.conf
# -------------------------------------------------------------------
ap_pwquality_conf_file () {
  : <<'AI_BLOCK'
EXPLANATION
Configure /etc/security/pwquality.conf with these exact settings:
  minlen = 10
  minclass = 2
  maxrepeat = 2
  maxclassrepeat = 6
  lcredit = -1
  ucredit = -1
  dcredit = -1
  ocredit = -1
  maxsequence = 2
  difok = 5
  gecoscheck = 1

AI_PROMPT
Return only Bash code (no markdown, no prose).
Requirements:
- Target file: /etc/security/pwquality.conf.
- Create a timestamped backup before editing.
- For each key above:
  - If present (commented or uncommented), set it to the exact value.
  - If missing, append "key = value" on its own line.
- Keep changes idempotent.
- Print a short confirmation after applying settings.
AI_BLOCK
#!/bin/bash
set -euo pipefail

ua_configure_pwquality() {
  file="/etc/security/pwquality.conf"
  backup="${file}.$(date +%F_%H-%M-%S).bak"

  echo "Creating backup of $file at $backup"
  sudo cp "$file" "$backup"

  declare -A settings=(
    [minlen]=10
    [minclass]=2
    [maxrepeat]=2
    [maxclassrepeat]=6
    [lcredit]=-1
    [ucredit]=-1
    [dcredit]=-1
    [ocredit]=-1
    [maxsequence]=2
    [difok]=5
    [gecoscheck]=1
  )

  for key in "${!settings[@]}"; do
    value="${settings[$key]}"
    if grep -Eq "^[#\s]*${key}\s*=" "$file"; then
      sudo sed -i "s|^[#\s]*${key}\s*=.*|${key} = ${value}|" "$file"
    else
      echo "${key} = ${value}" | sudo tee -a "$file" >/dev/null
    fi
  done

  echo "pwquality.conf successfully configured."
}

ua_configure_pwquality

}

# -------------------------------------------------------------------
# Configure pam_faillock in common-auth/common-account
# -------------------------------------------------------------------
ap_lockout_faillock () {
  : <<'AI_BLOCK'
EXPLANATION
Configure account lockout using pam_faillock on Debian/Ubuntu/Mint.

Required lines (exact spacing not critical, order matters):
  In /etc/pam.d/common-auth (around pam_unix.so):
    auth        required      pam_faillock.so preauth
    auth        [default=die] pam_faillock.so authfail
    auth        sufficient    pam_faillock.so authsucc
  In /etc/pam.d/common-account:
    account     required      pam_faillock.so

AI_PROMPT
Return only Bash code (no markdown, no prose).
Requirements:
- Create timestamped backups of both files before editing.
- In /etc/pam.d/common-auth:
  - Ensure the three auth lines exist exactly once each.
  - Place the preauth line before pam_unix.so; ensure authfail follows appropriately; ensure authsucc is present.
- In /etc/pam.d/common-account:
  - Ensure the account line exists exactly once.
- Keep the edit idempotent (no duplicates on subsequent runs).
- Print simple confirmations indicating which lines were added or already present.
AI_BLOCK
#!/bin/bash
set -euo pipefail

ua_configure_pam_faillock() 
  auth_file="/etc/pam.d/common-auth"
  account_file="/etc/pam.d/common-account"
  ts=$(date +%F_%H-%M-%S)
  sudo cp "$auth_file" "${auth_file}.${ts}.bak"
  sudo cp "$account_file" "${account_file}.${ts}.bak"

  declare -a auth_lines=(
    "auth        required      pam_faillock.so preauth"
    "auth        [default=die] pam_faillock.so authfail"
    "auth        sufficient    pam_faillock.so authsucc"
  )

  echo "Configuring $auth_file..."
  for line in "${auth_lines[@]}"; do
    if ! grep -Fxq "$line" "$auth_file"; then
      case "$line" in
        *preauth*)
          sudo sed -i "/pam_unix.so/i $line" "$auth_file"
          ;;
        *authfail*)
          sudo sed -i "/pam_unix.so/a $line" "$auth_file"
          ;;
        *authsucc*)
          if ! grep -Fxq "$line" "$auth_file"; then
            echo "$li

}
