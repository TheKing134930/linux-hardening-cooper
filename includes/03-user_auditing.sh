#!/usr/bin/env bash
set -euo pipefail

invoke_user_auditing () {
  echo -e "${CYAN}[User Auditing] Start${NC}"

  ua_audit_interactive_remove_unauthorized_users
  ua_audit_interactive_remove_unauthorized_sudoers
  ua_force_temp_passwords
  ua_remove_non_root_uid0
  ua_set_password_aging_policy
  ua_set_shells_standard_and_root_bash
  ua_set_shells_system_accounts_nologin

  echo -e "${CYAN}[User Auditing] Done${NC}"
}

# -------------------------------------------------------------------
# 1) Interactive audit of local users with valid login shells
# -------------------------------------------------------------------

#!/bin/bash

a_audit_interactive_remove_unauthorized_users() {
  : <<'AI_BLOCK'
EXPLANATION
Enumerate local accounts that have a valid login shell (from /etc/shells). For each such user,
prompt: "Is <user> an Authorized User? [Y/n]". Default to Y when the user presses Enter.
If the answer is 'n' or 'N', remove the account and its home directory.

AI_PROMPT
Return only Bash code (no markdown, no prose).
Requirements:
- Build the list of valid shells from /etc/shells, excluding comments/blank lines.
- From getent passwd, select accounts whose shell is in that list; emit usernames only.
- For each username:
  - Prompt exactly: "Is <user> an Authorized User? [Y/n] " and read input.
  - Treat empty input as 'Y' (default).
  - If input matches 'n' or 'N', delete the user and its home (-r / -f as appropriate), then print a confirmation line.
  - Otherwise print that the user is authorized.
- Continue on errors for any single user so the loop completes.
AI_BLOCK

  #!/bin/bash
set -euo pipefail

ua_audit_interactive_remove_unauthorized_users() {
  # Build a list of valid shells from /etc/shells (ignore comments and blanks)
  valid_shells=$(grep -vE '^(#|$)' /etc/shells)

  # Get usernames with shells in the valid list
  users=$(getent passwd | while IFS=: read -r user _ _ _ _ _ shell; do
    if echo "$valid_shells" | grep -qx "$shell"; then
      echo "$user"
    fi
  done)

  # Loop through each user
  for u in $users; do
    read -p "Is $u an Authorized User? [Y/n] " ans
    ans=${ans:-Y}

    if [[ "$ans" =~ ^[Nn]$ ]]; then
      if sudo deluser --remove-home "$u" >/dev/null 2>&1; then
        echo "Removed unauthorized user: $u"
      else
        echo "Failed to remove user: $u (continuing)"
      fi
    else
      echo "$u is authorized."
    fi
  done
}

ua_audit_interactive_remove_unauthorized_users

}

# -------------------------------------------------------------------
# 2) Interactive audit of sudoers; remove unauthorized admins
# -------------------------------------------------------------------
ua_audit_interactive_remove_unauthorized_sudoers() {
  : <<'AI_BLOCK'
  (sudoer audit explanation and requirements go here)
AI_BLOCK
}

  : <<'AI_BLOCK'
  EXPLANATION
List current members of the 'sudo' group and ask per-user whether they should remain an admin.
Default answer is Y. If the answer is 'n' or 'N', remove that user from 'sudo'.

AI_PROMPT
Return only Bash code (no markdown, no prose).
Requirements:
- Get the member list from: getent group sudo (fourth field), split on commas into usernames.
- For each user:
  - Prompt exactly: "Is <user> an Authorized Administrator? [Y/n] " and read input.
  - Default to Y on empty input.
  - On 'n' or 'N', remove the user from sudo with the Debian-family tool (deluser <user> sudo) and print a confirmation.
  - Otherwise print that the user is authorized.
- Continue on errors so the loop completes.
AI_BLOCK

#!/bin/bash
set -euo pipefail

ua_audit_interactive_remove_unauthorized_sudoers() {
  # Get members of the sudo group
  sudo_members=$(getent group sudo | awk -F: '{print $4}' | tr ',' ' ')

  # Loop through each sudo member
  for user in $sudo_members; do
    read -p "Is $user an Authorized Administrator? [Y/n] " ans
    ans=${ans:-Y}

    if [[ "$ans" =~ ^[Nn]$ ]]; then
      if sudo deluser "$user" sudo >/dev/null 2>&1; then
        echo "Removed $user from sudo group."
      else
        echo "Failed to remove $user from sudo group (continuing)."
      fi
    else
      echo "$user is authorized."
    fi
  done
}

ua_audit_interactive_remove_unauthorized_sudoers

# -------------------------------------------------------------------
# 3) Force temporary passwords for all users
# -------------------------------------------------------------------
ua_force_temp_passwords () {
  : <<'AI_BLOCK'
EXPLANATION
Set a temporary password for every local account using SHA-512 hashing with chpasswd.
If $TEMP_PASSWORD is set, use it; otherwise use the default "1CyberPatriot!".

AI_PROMPT
Return only Bash code (no markdown, no prose).
Requirements:
- Determine the password as: ${TEMP_PASSWORD:-1CyberPatriot!}.
- Iterate over all usernames from getent passwd.
- For each username, set "<user>:<password>" via chpasswd with SHA-512.
- Continue on errors so one failure does not stop the loop.
- Print a brief status line per user or a final summary.
AI_BLOCK

#!/bin/bash
set -euo pipefail

ua_force_temp_passwords() {
  password="${TEMP_PASSWORD:-1CyberPatriot!}"

  echo "Setting temporary passwords for all local accounts..."
  while IFS=: read -r user _; do
    if sudo chpasswd -e <<<"$(printf "%s:%s\n" "$user" "$(openssl passwd -6 "$password")")" >/dev/null 2>&1; then
      echo "Set temporary password for $user"
    else
      echo "Failed to set password for $user (continuing)"
    fi
  done < <(getent passwd)

  echo "Password reset process complete."
}

ua_force_temp_passwords

}

# -------------------------------------------------------------------
# 4) Remove any UID 0 accounts that are not 'root'
# -------------------------------------------------------------------
ua_remove_non_root_uid0 () {
  : <<'AI_BLOCK'
EXPLANATION
Find accounts with UID 0 other than 'root' and remove them (including home directories).

AI_PROMPT
Return only Bash code (no markdown, no prose).
Requirements:
- Parse /etc/passwd (or getent) for entries with UID exactly 0 where the username != root.
- For each such username:
  - Delete the user and its home directory (force where appropriate).
  - Print a confirmation line.
- Continue on errors so the loop completes.
AI_BLOCK

#!/bin/bash
set -euo pipefail

ua_remove_non_root_uid0() {
  echo "Checking for non-root UID 0 accounts..."
  getent passwd | awk -F: '$3 == 0 && $1 != "root" {print $1}' | while read -r user; do
    if sudo deluser --remove-home "$user" >/dev/null 2>&1; then
      echo "Removed unauthorized UID 0 account: $user"
    else
      echo "Failed to remove UID 0 account: $user (continuing)"
    fi
  done
  echo "UID 0 account audit complete."
}

ua_remove_non_root_uid0

}

# -------------------------------------------------------------------
# 5) Set password aging policy for all users (Debian family)
# -------------------------------------------------------------------
ua_set_password_aging_policy () {
  : <<'AI_BLOCK'
EXPLANATION
Apply a simple password aging policy to every local account: max age 60 days, min age 10 days, warn 7 days.

AI_PROMPT
Return only Bash code (no markdown, no prose).
Requirements:
- Iterate over all usernames from getent passwd.
- For each username, run the chage command with: -M 60 -m 10 -W 7.
- Continue on errors; print minimal status or a final summary.
AI_BLOCK

#!/bin/bash
set -euo pipefail

ua_set_password_aging_policy() {
  echo "Applying password aging policy to all local accounts..."
  getent passwd | while IFS=: read -r user _; do
    if sudo chage -M 60 -m 10 -W 7 "$user" >/dev/null 2>&1; then
      echo "Set password aging policy for $user"
    else
      echo "Failed to set password aging policy for $user (continuing)"
    fi
  done
  echo "Password aging policy applied to all accounts."
}

ua_set_password_aging_policy
}

# -------------------------------------------------------------------
# 6) Set shells for standard users and root to /bin/bash
# -------------------------------------------------------------------
ua_set_shells_standard_and_root_bash () {
  : <<'AI_BLOCK'
EXPLANATION
Change the login shell to /bin/bash for accounts with UID 0 (root) and for standard users (UID >= 1000).

AI_PROMPT
Return only Bash code (no markdown, no prose).
Requirements:
- Read /etc/passwd line by line.
- If UID is 0 or >= 1000, set the shell to /bin/bash using usermod -s.
- Print "Changed shell for <user> to /bin/bash." for each change.
- Continue on errors so the loop completes.
AI_BLOCK
#!/bin/bash
set -euo pipefail

ua_set_shells_standard_and_root_bash() {
  echo "Setting login shell to /bin/bash for root and standard users..."
  while IFS=: read -r user _ uid _ _ _ _; do
    if [[ "$uid" -eq 0 || "$uid" -ge 1000 ]]; then
      if sudo usermod -s /bin/bash "$user" >/dev/null 2>&1; then
        echo "Changed shell for $user to /bin/bash."
      else
        echo "Failed to change shell for $user (continuing)"
      fi
    fi
  done < /etc/passwd
  echo "Shell update complete."
}

ua_set_shells_standard_and_root_bash
}


# 7) Set shells for system accounts to /usr/sbin/nologin
# -------------------------------------------------------------------
#!/bin/bash
set -euo pipefail

ua_set_system_account_shells_nologin() {
  echo "Setting login shell to /usr/sbin/nologin for system accounts..."
  while IFS=: read -r user _ uid _ _ _ _; do
    if [[ "$uid" -ge 1 && "$uid" -le 999 ]]; then
      if sudo usermod -s /usr/sbin/nologin "$user" >/dev/null 2>&1; then
        echo "Changed shell for $user to /usr/sbin/nologin."
      else
        echo "Failed to change shell for $user (continuing)"
      fi
    fi
  done < /etc/passwd
  echo "System account shell update complete."
}

ua_set_system_account_shells_nologin