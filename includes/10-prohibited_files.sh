#!/usr/bin/env bash
set -euo pipefail

invoke_prohibited_files () {
  echo -e "${CYAN}[Prohibited Files] Start${NC}"

  pf_remove_prohibited_files

  echo -e "${CYAN}[Prohibited Files] Done${NC}"
}

# -------------------------------------------------------------------
# Remove files matching extensions from $FILE_EXTENSIONS
# -------------------------------------------------------------------
pf_remove_prohibited_files () {
  # Ensure FILE_EXTENSIONS is set and is an array with at least one item
  if [ -z "${FILE_EXTENSIONS+x}" ] || [ ${#FILE_EXTENSIONS[@]} -eq 0 ]; then
    echo "No file extensions configured."
    return
  fi

  local ext
  local total_deleted=0

  for ext in "${FILE_EXTENSIONS[@]}"; do
    # Trim leading/trailing whitespace
    ext="$(echo "${ext}" | xargs)"
    [ -z "$ext" ] && continue

    echo "Searching and removing files with .${ext} extension..."

    # Use find to locate regular files and attempt to delete them one by one to continue on error
    while IFS= read -r -d $'\0' file; do
      if sudo rm -f -- "$file" 2>/dev/null; then
        total_deleted=$((total_deleted+1))
      else
        # deletion failed; print a minimal warning but continue
        echo "Warning: failed to remove $file"
      fi
    done < <(find / -type f -name "*.${ext}" -print0 2>/dev/null)
  done

  echo "Prohibited file removal complete. Files deleted: ${total_deleted}"
}
