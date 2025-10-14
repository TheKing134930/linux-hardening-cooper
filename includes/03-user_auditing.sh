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
ua_audit_interactive_remove_unauthorized_users () {
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

// ...existing code...
ua_audit_interactive_remove_unauthorized_users () {
  # Build list of valid shells from /etc/shells (exclude comments/blank)
  mapfile -t valid_shells < <(grep -Ev '^\s*#|^\s*$' /etc/shells 2>/dev/null || true)

  declare -A shell_ok=()
  for s in "${valid_shells[@]}"; do
    shell_ok["$s"]=1
  done

  # Enumerate accounts and check their shell against the valid list
  while IFS=: read -r username _ _ _ _ _ shell; do
    [ -z "$username" ] && continue
    if [[ -n "${shell_ok[$shell]:-}" ]]; then
      printf "Is %s an Authorized User? [Y/n] " "$username"
      if ! read -r reply; then
        reply=Y
      fi
      reply=${reply:-Y}

      if [[ "$reply" == [Nn] ]]; then
        if sudo userdel -r "$username" >/dev/null 2>&1; then
          echo "User $username deleted."
        elif sudo userdel -f -r "$username" >/dev/null 2>&1; then
          echo "User $username forcefully deleted."
        elif sudo userdel -f "$username" >/dev/null 2>&1; then
          echo "User $username forcefully deleted."
        else
          echo "Failed to delete user $username."
        fi
      else
        echo "User $username is authorized."
      fi
    fi
  done < <(getent passwd)
}
// ...existing code...
}

# -------------------------------------------------------------------
# 2) Interactive audit of sudoers; remove unauthorized admins
# -------------------------------------------------------------------
ua_audit_interactive_remove_unauthorized_sudoers () {
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

members="$(getent group sudo | cut -d: -f4)"
echo "Current sudo group members: ${members:-<none>}"
IFS=',' read -r -a users <<< "$members"
for user in "${users[@]}"; do
[ -z "$user" ] && continue
printf 'Is %s an Authorized Administrator? [Y/n] ' "$user"
read -r ans
[ -z "$ans" ] && ans=Y
if [[ "$ans" == [Nn] ]]; then
if sudo deluser "$user" sudo >/dev/null 2>&1; then
echo "Removed $user from sudo."
else
echo "Warning: Failed to remove $user from sudo."
fi
else
echo "$user is authorized."
fi
done
}

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

PASSWORD="${TEMP_PASSWORD:-1CyberPatriot!}"
success=0
failure=0

while IFS=: read -r user _; do
    if printf '%s:%s\n' "$user" "$PASSWORD" | chpasswd --crypt-method SHA512 2>/dev/null; then
        echo "User $user: password set."
        success=$((success + 1))
    else
        echo "User $user: failed to set password."
        failure=$((failure + 1))
    fi
done < <(getent passwd)

echo "Summary: $success succeeded, $failure failed."

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

getent passwd | awk -F: '$3 == 0 && $1 != "root" { print $1 }' | while read -r user; do
    if userdel -r "$user" 2>/dev/null; then
        echo "User $user deleted."
    elif userdel -f "$user" 2>/dev/null; then
        echo "User $user forcefully deleted."
    else
        echo "Failed to delete user $user."
    fi
done

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

success=0
failure=0

getent passwd | cut -d: -f1 | while read -r user; do
    if chage -M 60 -m 10 -W 7 "$user" 2>/dev/null; then
        success=$((success + 1))
    else
        failure=$((failure + 1))
    fi
done

echo "Password policy updated: $success succeeded, $failure failed."

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
while IFS=: read -r user _ uid _ _ _ _; do
if [ "$uid" -eq 0 ] || [ "$uid" -ge 1000 ]; then
if usermod -s /bin/bash "$user" 2>/dev/null; then
echo "Changed shell for $user to /bin/bash."
else
echo "Failed to change shell for $user."
fi
fi
done < /etc/passwd
}

# -------------------------------------------------------------------
# 7) Set shells for system accounts to /usr/sbin/nologin
# -------------------------------------------------------------------
ua_set_shells_system_accounts_nologin () {
  : <<'AI_BLOCK'
EXPLANATION
For system accounts (UID 1..999), set the shell to /usr/sbin/nologin.

AI_PROMPT
Return only Bash code (no markdown, no prose).
Requirements:
- Read /etc/passwd line by line.
- If UID is between 1 and 999 inclusive, set the shell to /usr/sbin/nologin using usermod -s.
- Print "Changed shell for <user> to /usr/sbin/nologin." for each change.
- Continue on errors so the loop completes.
AI_BLOCK
while IFS=: read -r user _ uid _ _ _ _; do
if [ "$uid" -ge 1 ] && [ "$uid" -le 999 ]; then
if usermod -s /usr/sbin/nologin "$user" 2>/dev/null; then
echo "Changed shell for $user to /usr/sbin/nologin."
else
echo "Failed to change shell for $user."
fi
fi
done < /etc/passwd
}
