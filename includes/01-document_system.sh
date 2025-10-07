# Document the system before making changes.
invoke_document_system () {
echo "Running Documenting System..."
# Placeholder for Documenting System functionality

# Create directory for storing documentation if it doesn't exist
mkdir -p "$DOCS"
    
# Get a list of all usernames on the system
cut -d: -f1 /etc/passwd > "$DOCS/users.txt"

# Get a list of all users in the sudo group
getent group sudo | cut -d: -f4 | tr ',' '\n' > "$DOCS/admins.txt"

# Get a list of all apt packages installed
dpkg --get-selections | awk '{print $1}' > "$DOCS/packages.txt"

# Get a list of all snap packages installed
snap list > "$DOCS/snap.txt"

# Get a list of all listening services
ss -plnt > "$DOCS/listening.txt"

# Get a refined list of services that are listening for clients and store it in listening_services.txt
ss -plnt | awk 'NR>1 {print $NF}' | awk -F, '{print $1}' | sort | uniq | grep -oP '"\K[^"]+' > "$DOCS/listening_services.txt"
	
# Document all cron jobs
for user in $(cut -f1 -d: /etc/passwd); do echo "Cron jobs for user: $user" >> "$DOCS/cron.txt"; crontab -u $user -l >> "$DOCS/cron.txt" 2>/dev/null; echo "" >> "$DOCS/cron.txt"; done

# Get system-wide cron jobs
cat /etc/crontab /etc/cron.d/* >> "$DOCS/cron.txt"

# Listening Malware Search
for pid in $(sudo ss -plnt | grep -oP 'pid=\K\d+' | sort -u); do cmdline=$(tr -d '\0' < /proc/$pid/cmdline 2>/dev/null); if [ -n "$cmdline" ]; then echo "PID: $pid - Command Line: $cmdline" >> "$DOCS/premalware.txt"; fi; done

# Comapare Vanilla Packages to Installed Packages
for I in $CURDPKG; do if [[ $VANILLA != *"$I"* ]]; then echo $I >> $DOCS/suspackages.txt; fi; done
}