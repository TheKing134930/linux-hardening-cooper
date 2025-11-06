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
# Loop through all users and remove unauthorized users
BOLD_RED='\033[1;31m'
BOLD_GREEN='\033[1;32m'
shells=$(cat /etc/shells | grep -vE '(^#|^$)')
users=$(getent passwd | awk -F: -v shells="$shells" 'BEGIN { split(shells, shellArray, "\n") } { for (i in shellArray) if ($7 == shellArray[i]) print $1 }')

    for user in $users; do
    # Prompt for authorization, default to 'Y'
		echo -e "Is ${BOLD_GREEN}${user}${NC} an Authorized User? [Y/n] "
		read answer
        answer=${answer:-Y}  # Default to 'Y' if no input

        if [[ $answer =~ ^[nN]$ ]]; then
			echo -e "Removing user ${BOLD_RED}${user}${NC} and their home directory..."
            userdel -rf "$user"
			echo -e "User ${BOLD_RED}${user}${NC} removed."
            echo -e "\n"
        else
            echo -e "User ${BOLD_GREEN}${user}${NC} is authorized."
            echo -e "\n"
        fi
    done
  }


# -------------------------------------------------------------------
# 2) Interactive audit of sudoers; remove unauthorized admins
# -------------------------------------------------------------------

ua_audit_interactive_remove_unauthorized_sudoers() {
  # Get members of the sudo group
  sudo_members=$(getent group sudo | awk -F: '{print $4}' | tr ',' ' ')

  # Loop through each sudo member
  for user in $sudo_members; do
    read -p "Is $user an Authorized Administrator? [Y/n] " ans
    ans=${ans:-Y}

    if [[ $ans =~ ^[Nn] ]]; then
      if sudo deluser "$user" sudo >/dev/null 2>&1; then
        echo "Removed $user from sudo group."
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
  local PASSWORD="${TEMP_PASSWORD:-1CyberPatriot!}"
  local success=0 failure=0 user

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

# 7) Set shells for system accounts to /usr/sbin/nologin
ua_set_shells_system_accounts_nologin() {
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
