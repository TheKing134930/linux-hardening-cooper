#!/usr/bin/env bash
set -euo pipefail

invoke_account_policy () {
  echo -e "${CYAN}[Account Policy] Start${NC}"

  ap_secure_login_defs
  ap_blankpasswords_disallow
  ap_pam_unixso
  ap_pwquality_install
  ensure_pwhistory_line
  ap_pwquality_conf_file
  ap_lockout_faillock

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
# Strong password encryption and password history
# -------------------------------------------------------------------
ap_pam_unixso () {
backup="/etc/pam.d/common-password.$(date +%Y%m%d%H%M%S).bak"
file="/etc/pam.d/common-password"
sudo sed -i 's/pam_unix.so.*/pam_unix.so obscure use_authtok try_first_pass yescrypt/g' $file
}

ap_pwquality_install {
  pkg="libpam-pwquality"

  if dpkg -s "$pkg" >/dev/null 2>&1; then
    echo "$pkg is already installed."
    return 0
  fi

  echo "Installing $pkg ..."
  if [[ $EUID -ne 0 ]]; then
    sudo apt-get update -y
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg"
  else
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg"
  fi
}

ensure_pwhistory_line() {
  set -euo pipefail
  local file="/etc/pam.d/common-password"
  local backup="${file}.$(date +%F_%H-%M-%S).bak"
  local remember="${1:-10}"
  local extra_opts="${2:-}"   # e.g., "enforce_for_root"

  local line="password    required                        pam_pwhistory.so remember=${remember}${extra_opts:+ ${extra_opts}}"

  echo "Backing up $file -> $backup"
  sudo cp -a "$file" "$backup"

  # Already present?
  if grep -Eq '^[[:space:]]*password[[:space:]]+.*pam_pwhistory\.so\b' "$file"; then
    echo "pam_pwhistory line already present; no change."
    return 0
  fi

  # Insert before the first pam_unix.so password line; else append
  if grep -Eq '^[[:space:]]*password[[:space:]].*pam_unix\.so\b' "$file"; then
    sudo sed -i --follow-symlinks \
'0,/^[[:space:]]*password[[:space:]].*pam_unix\.so\b/{
/^[[:space:]]*password[[:space:]].*pam_unix\.so\b/i '"$line"'
}' "$file"
    echo "Inserted pam_pwhistory before pam_unix.so."
  else
    echo "$line" | sudo tee -a "$file" >/dev/null
    echo "pam_unix.so not found; appended pam_pwhistory at end."
  fi
}

# -------------------------------------------------------------------
# Configure /etc/security/pwquality.conf
# -------------------------------------------------------------------
ap_pwquality_conf_file () {
  set -euo pipefail

  file="/etc/security/pwquality.conf"
  backup="${file}.$(date +%F_%H-%M-%S).bak"

  echo "Creating backup of $file at $backup"
  if [[ -f "$file" ]]; then
    sudo cp -a "$file" "$backup"
  else
    # create an empty file with sensible perms if it doesn't exist
    echo "# created by ap_pwquality_conf_file" | sudo tee "$file" >/dev/null
    sudo chmod 0644 "$file"
  fi

  # Desired settings (values can be changed here)
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

  # Deterministic key order (associative arrays iterate unpredictably)
  keys=(minlen minclass maxrepeat maxclassrepeat lcredit ucredit dcredit ocredit maxsequence difok gecoscheck)

  for key in "${keys[@]}"; do
    value="${settings[$key]}"
    # If a line exists (commented or not), replace it; else append
    if grep -Eq "^[[:space:]#]*${key}[[:space:]]*=" "$file"; then
      sudo sed -i -E "s|^[[:space:]#]*(${key})[[:space:]]*=.*|\1 = ${value}|g" "$file"
    else
      echo "${key} = ${value}" | sudo tee -a "$file" >/dev/null
    fi
  done

  # Ensure newline at EOF (some tools are picky)
  sudo sed -i -e '$a\' "$file"

  echo "pwquality.conf successfully configured."
}


# -------------------------------------------------------------------
# Configure pam_faillock in common-auth/common-account
# -------------------------------------------------------------------
ap_lockout_faillock () {
pam_file="/etc/pam.d/common-auth"

## preauth 
# If "pam_faillock.so ... preauth" isn't already present:
if ! grep -Eq '^[[:space:]]*auth[[:space:]]+required[[:space:]]+pam_faillock\.so([[:space:]]+.*)?\bpreauth\b' "$pam_file"; then
  if grep -Eq '^[[:space:]]*auth[[:space:]].*pam_unix\.so' "$pam_file"; then
    # Insert once before the first pam_unix.so auth line
    sudo sed -i --follow-symlinks \
      '0,/^[[:space:]]*auth[[:space:]].*pam_unix\.so/{/^[[:space:]]*auth[[:space:]].*pam_unix\.so/i auth    required                        pam_faillock.so preauth
}' "$pam_file"
  else
    # Fallback: no pam_unix.so line found; append
    echo "auth    required                        pam_faillock.so preauth" | sudo tee -a "$pam_file" >/dev/null
  fi
fi

## authfail
# Skip if an authfail line is already there (comment- and whitespace-tolerant)
if ! grep -Eq '^[[:space:]]*auth[[:space:]]+\[default=die\][[:space:]]+pam_faillock\.so([[:space:]]+.*)?\bauthfail\b' "$pam_file"; then
  if grep -Eq '^[[:space:]]*auth[[:space:]].*pam_unix\.so' "$pam_file"; then
    # Insert once, right after the FIRST pam_unix.so auth line (not commented)
    sudo sed -i --follow-symlinks \
'0,/^[[:space:]]*auth[[:space:]].*pam_unix\.so/{
/^[[:space:]]*auth[[:space:]].*pam_unix\.so/a auth    [default=die]                        pam_faillock.so authfail
}' "$pam_file"
  else
    # Fallback if no pam_unix.so auth line exists
    echo "auth    [default=die]                        pam_faillock.so authfail" | sudo tee -a "$pam_file" >/dev/null
  fi
fi

## authsucc
# If 'auth sufficient pam_faillock.so authsucc' not present, insert it
if ! grep -Eq '^[[:space:]]*auth[[:space:]]+sufficient[[:space:]]+pam_faillock\.so([[:space:]]+.*)?\bauthsucc\b' "$pam_file"; then
  if grep -Eq '^[[:space:]]*auth[[:space:]].*pam_faillock\.so([[:space:]]+.*)?\bauthfail\b' "$pam_file"; then
    sudo sed -i --follow-symlinks \
'0,/^[[:space:]]*auth[[:space:]].*pam_faillock\.so.*authfail/{
/^[[:space:]]*auth[[:space:]].*pam_faillock\.so.*authfail/a auth    sufficient                        pam_faillock.so authsucc
}' "$pam_file"
  elif grep -Eq '^[[:space:]]*auth[[:space:]].*pam_unix\.so' "$pam_file"; then
    sudo sed -i --follow-symlinks \
'0,/^[[:space:]]*auth[[:space:]].*pam_unix\.so/{
/^[[:space:]]*auth[[:space:]].*pam_unix\.so/a auth    sufficient                        pam_faillock.so authsucc
}' "$pam_file"
  else
    echo "auth    sufficient                        pam_faillock.so authsucc" | sudo tee -a "$pam_file" >/dev/null
  fi
fi

## faillock.conf
fail_file="/etc/security/faillock.conf"
backup="${fail_file}.$(date +%F_%H-%M-%S).bak"
sudo cp -a "$fail_file" "$backup"

declare -A kv_settings=([deny]=5 [fail_interval]=900 [unlock_time]=600)
flags=(audit silent)

# key=value
for key in "${!kv_settings[@]}"; do
  val="${kv_settings[$key]}"
  if grep -Eq "^[[:space:]#]*${key}[[:space:]]*=" "$fail_file"; then
    sudo sed -i -E "s|^[[:space:]#]*(${key})[[:space:]]*=.*|\1 = ${val}|" "$fail_file"
  else
    echo "${key} = ${val}" | sudo tee -a "$fail_file" >/dev/null
  fi
done

# flags (no value) — note: no alternation; use [[:space:]]*$ instead
for flag in "${flags[@]}"; do
  if grep -Eq "^[[:space:]#]*${flag}([[:space:]]|$)" "$fail_file"; then
    sudo sed -i -E "s|^[[:space:]#]*(${flag})[[:space:]]*$|\1|" "$fail_file"
  else
    echo "$flag" | sudo tee -a "$fail_file" >/dev/null
  fi
done


echo "faillock.conf successfully configured."

}
