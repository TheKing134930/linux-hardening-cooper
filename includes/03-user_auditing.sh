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

mapfile -t valid_shells < <(grep -Ev '^\s*#|^\s*$' /etc/shells)

while IFS=: read -r username _ _ _ _ _ shell; do
    for valid_shell in "${valid_shells[@]}"; do
        if [[ "$shell" == "$valid_shell" ]]; then
            echo -n "Is $username an Authorized User? [Y/n] "
            read -r reply
            reply=${reply:-Y}
            if [[ "$reply" == [Nn] ]]; then
                if userdel -r "$username" 2>/dev/null; then
                    echo "User $username deleted."
                else
                    userdel -f "$username" 2>/dev/null && echo "User $username forcefully deleted."
                fi
            else
                echo "User $username is authorized."
            fi
            break
        fi
    done
done < <(getent passwd)

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

IFS=: read -r _ _ _ users <<< "$(getent group sudo)"
IFS=, read -ra user_list <<< "$users"

for user in "${user_list[@]}"; do
    echo -n "Is $user an Authorized Administrator? [Y/n] "
    read -r reply
    reply=${reply:-Y}
    if [[ "$reply" == [Nn] ]]; then
        if deluser "$user" sudo 2>/dev/null; then
            echo "User $user removed from sudo group."
        else
            echo "Failed to remove user $user from sudo group."
        fi
    else
        echo "User $user is authorized."
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
}
