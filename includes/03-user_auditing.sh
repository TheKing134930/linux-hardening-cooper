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

    # ...existing code...
  ua_audit_interactive_remove_unauthorized_users () {
  mapfile -t valid_shells < <(grep -Ev '^\s*#|^\s*$' /etc/shells 2>/dev/null || true)
  declare -A shell_ok=()
  for s in "${valid_shells[@]}"; do
    shell_ok["$s"]=1
  done

  while IFS=: read -r username _ _ _ _ _ shell; do
    [ -z "$username" ] && continue
    [ -z "$shell" ] && continue

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

  # ...existing code...
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

ua_audit_interactive_remove_unauthorized_sudoers () {
  members="$(getent group sudo 2>/dev/null | cut -d: -f4)"
  IFS=',' read -r -a users <<< "${members:-}"

  for user in "${users[@]}"; do
    user="$(echo "$user" | xargs)"
    [ -z "$user" ] && continue

    printf "Is %s an Authorized Administrator? [Y/n] " "$user"
    if ! read -r ans; then
      ans=Y
    fi
    ans=${ans:-Y}

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
```// filepath: c:\Users\jacob\Team Script\linux-hardening-cooper\includes\03-user_auditing.sh
ua_audit_interactive_remove_unauthorized_sudoers () {
  members="$(getent group sudo 2>/dev/null | cut -d: -f4)"
  echo "Current sudo group members: ${members:-<none>}"
  IFS=',' read -r -a users <<< "${members:-}"

  for user in "${users[@]}"; do
    user="$(echo "$user" | xargs)"
    [ -z "$user" ] && continue

    printf "Is %s an Authorized Administrator? [Y/n] " "$user"
    if ! read -r ans; then
      ans=Y
    fi
    ans=${ans:-Y}

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
>> 

ua_force_temp_passwords () {
  local PASSWORD="${TEMP_PASSWORD:-1CyberPatriot!}"
  local success=0
  local failure=0
  local user

  while IFS=: read -r user _; do
    [ -z "$user" ] && continue
    if printf '%s:%s\n' "$user" "$PASSWORD" | sudo chpasswd --crypt-method SHA512 >/dev/null 2>&1; then
      echo "User $user: password set."
      success=$((success + 1))
    else
      echo "User $user: failed to set password."
      failure=$((failure + 1))
    fi
  done < <(getent passwd 2>/dev/null || true)

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

ua_remove_non_root_uid0 () {
  getent passwd | awk -F: '$3 == 0 && $1 != "root" { print $1 }' | while IFS= read -r user; do
    [ -z "$user" ] && continue
    if sudo userdel -r "$user" >/dev/null 2>&1; then
      echo "User $user deleted."
    elif sudo userdel -f -r "$user" >/dev/null 2>&1; then
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
ua_set_password_aging_policy () {
  local success=0 failure=0 user

  while IFS=: read -r user _; do
    [ -z "$user" ] && continue
    if sudo chage -M 60 -m 10 -W 7 "$user" >/dev/null 2>&1; then
      echo "Set aging for $user."
      success=$((success + 1))
    else
      echo "Failed to set aging for $user."
      failure=$((failure + 1))
    fi
  done < <(getent passwd 2>/dev/null || true)

  echo "Password aging: $success succeeded, $failure failed."
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
# ...existing code...
ua_set_shells_standard_and_root_bash () {
  while IFS=: read -r username _ uid _ _ _ _; do
    [ -z "$username" ] && continue
    case "$uid" in
      ''|*[!0-9]*) continue ;;
    esac

    if [ "$uid" -eq 0 ] || [ "$uid" -ge 1000 ]; then
      if sudo usermod -s /bin/bash "$username" >/dev/null 2>&1; then
        echo "Changed shell for $username to /bin/bash."
      else
        echo "Failed to change shell for $username."
      fi
    fi
  done < /etc/passwd
}
# ...existing code...
```// filepath: c:\Users\jacob\Team Script\linux-hardening-cooper\includes\03-user_auditing.sh
# ...existing code...
ua_set_shells_standard_and_root_bash () {
  while IFS=: read -r username _ uid _ _ _ _; do
    [ -z "$username" ] && continue
    case "$uid" in
      ''|*[!0-9]*) continue ;;
    esac

    if [ "$uid" -eq 0 ] || [ "$uid" -ge 1000 ]; then
      if sudo usermod -s /bin/bash "$username" >/dev/null 2>&1; then
        echo "Changed shell for $username to /bin/bash."
      else
        echo "Failed to change shell for $username."
      fi
    fi
  done < /etc/passwd
}
# ...existing code...


# 7) Set shells for system accounts to /usr/sbin/nologin
# -------------------------------------------------------------------

ua_set_shells_system_accounts_nologin () {
#!/bin/bash
# Loop through all users with UID between 1 and 999 and change their shell

awk -F: '($3 >= 1 && $3 <= 999) {print $1}' /etc/passwd | while read user; do
        echo "Changing shell for $user to /usr/sbin/nologin"
    usermod -s /usr/sbin/nologin "$user"
    done

}
