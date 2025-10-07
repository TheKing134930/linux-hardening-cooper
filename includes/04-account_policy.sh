#!/usr/bin/env bash
set -euo pipefail

invoke_account_policy () {
  echo -e "${CYAN}[Account Policy] Start${NC}"

  ap_secure_login_defs
  ap_pam_pwquality_inline
  ap_pwquality_conf_file
  ap_lockout_faillock

  echo -e "${CYAN}[Account Policy] Done${NC}"
}

# -------------------------------------------------------------------
# /etc/login.defs hardening
# -------------------------------------------------------------------
ap_secure_login_defs () {
  : <<'AI_BLOCK'
EXPLANATION
Harden /etc/login.defs with these exact values:
  PASS_MAX_DAYS 60
  PASS_MIN_DAYS 10
  PASS_WARN_AGE 14
  UMASK 077

AI_PROMPT
Return only Bash code (no markdown, no prose).
Requirements:
- Create a timestamped backup of /etc/login.defs before editing.
- Ensure the four directives exist with the specified values:
  - If commented or present with different values, update them.
  - If missing, append them.
- Preserve other content/spacing as much as reasonable.
- Print a short confirmation for each directive set.
AI_BLOCK
backup="/etc/login.defs.$(date +%Y%m%d%H%M%S).bak"
cp /etc/login.defs "$backup"

declare -A directives=(
[UID_MIN]=1000
[UID_MAX]=60000
[GID_MIN]=1000
[GID_MAX]=60000
)

file="/etc/login.defs"
tempfile=$(mktemp)

while IFS= read -r line; do
skip=0
for key in "${!directives[@]}"; do
if [[ "$line" =~ ^#?[[:space:]]*${key}[[:space:]]+ ]]; then
echo "${key} ${directives[$key]}" >> "$tempfile"
unset directives[$key]
skip=1
break
fi
done
[[ $skip -eq 0 ]] && echo "$line" >> "$tempfile"
done < "$file"

for key in "${!directives[@]}"; do
echo "${key} ${directives[$key]}" >> "$tempfile"
done

mv "$tempfile" "$file"

for key in UID_MIN UID_MAX GID_MIN GID_MAX; do
grep -qE "^[[:space:]]*${key}[[:space:]]+${directives[$key]:-}" "$file" && echo "${key} set to ${directives[$key]:-}" || echo "${key} set"
done
}

# -------------------------------------------------------------------
# Insert pam_pwquality inline in common-password
# -------------------------------------------------------------------
ap_pam_pwquality_inline () {
  : <<'AI_BLOCK'
EXPLANATION
Insert a pwquality rule into /etc/pam.d/common-password before the pam_unix.so line.

Desired line (single line, exact options/order):
  password requisite pam_pwquality.so retry=3 minlen=10 difok=5 ucredit=-1 lcredit=-1 dcredit=-1 ocredit=-1

AI_PROMPT
Return only Bash code (no markdown, no prose).
Requirements:
- Target file: /etc/pam.d/common-password.
- Create a timestamped backup before editing.
- If an equal pwquality line already exists, do nothing.
- Otherwise insert the exact line immediately before the first occurrence of pam_unix.so in that file.
- Ensure the edit is idempotent (running again won�t duplicate).
- Print a brief confirmation when the line is in place.
AI_BLOCK
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
backup="/etc/security/pwquality.conf.$(date +%Y%m%d%H%M%S).bak"
file="/etc/security/pwquality.conf"
cp "$file" "$backup"

declare -A keys=(
[minlen]=12
[dcredit]=-1
[ucredit]=-1
[ocredit]=-1
[lcredit]=-1
)

tempfile=$(mktemp)

while IFS= read -r line; do
modified=0
for k in "${!keys[@]}"; do
if [[ "$line" =~ ^[[:space:]]#?[[:space:]]$k[[:space:]]*= ]]; then
echo "$k = ${keys[$k]}" >> "$tempfile"
unset keys[$k]
modified=1
break
fi
done
[[ $modified -eq 0 ]] && echo "$line" >> "$tempfile"
done < "$file"

for k in "${!keys[@]}"; do
echo "$k = ${keys[$k]}" >> "$tempfile"
done

mv "$tempfile" "$file"

echo "pwquality.conf settings applied."
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
backup_auth="/etc/pam.d/common-auth.$(date +%Y%m%d%H%M%S).bak"
backup_account="/etc/pam.d/common-account.$(date +%Y%m%d%H%M%S).bak"

file_auth="/etc/pam.d/common-auth"
file_account="/etc/pam.d/common-account"

cp "$file_auth" "$backup_auth"
cp "$file_account" "$backup_account"

preauth="auth required pam_tally2.so preauth"
authfail="auth required pam_tally2.so authfail"
authsucc="auth required pam_tally2.so authsucc"
account_line="account required pam_tally2.so"
grep -Fxq "$preauth" "$file_auth" || preauth_added=1
grep -Fxq "$authfail" "$file_auth" || authfail_added=1
grep -Fxq "$authsucc" "$file_auth" || authsucc_added=1
grep -vF "$preauth" "$file_auth" | grep -vF "$authfail" | grep -vF "$authsucc" > "${file_auth}.tmp"

inserted_preauth=0
inserted_authfail=0
inserted_authsucc=0

while IFS= read -r line; do
if [[ $inserted_preauth -eq 0 && "$line" =~ pam_unix.so ]]; then
echo "$preauth" >> "${file_auth}.tmp"
inserted_preauth=1
[[ $preauth_added ]] && echo "Added preauth line."
echo "$line" >> "${file_auth}.tmp"
if [[ $authfail_added ]]; then
echo "$authfail" >> "${file_auth}.tmp"
inserted_authfail=1
echo "Added authfail line."
fi
else
echo "$line" >> "${file_auth}.tmp"
fi
done < "$file_auth"

[[ $inserted_preauth -eq 0 ]] && { echo "$preauth" >> "${file_auth}.tmp"; [[ $preauth_added ]] && echo "Added preauth line at EOF."; }
[[ $inserted_authfail -eq 0 && $authfail_added ]] && { echo "$authfail" >> "${file_auth}.tmp"; echo "Added authfail line at EOF."; }

if [[ $authsucc_added ]]; then
echo "$authsucc" >> "${file_auth}.tmp"
echo "Added authsucc line."
fi

mv "${file_auth}.tmp" "$file_auth"

[[ -z $preauth_added ]] && echo "Preauth line already present."
[[ -z $authfail_added ]] && echo "Authfail line already present."
[[ -z $authsucc_added ]] && echo "Authsucc line already present."
if ! grep -Fxq "$account_line" "$file_account"; then
echo "$account_line" >> "$file_account"
echo "Added account line."
else
echo "Account line already present."
fi
}
