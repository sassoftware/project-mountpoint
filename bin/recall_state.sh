#!/usr/bin/env bash

# Copyright © 2026, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# recall_state.sh
# Source this file to get three helper functions:
#  - init_recall
#  - add_my_var NAME
#  - add_my_alias NAME 
#  - recall [--file]
# Example:
#   source ~/recall_state.sh
#   init_recall
#   export MY_REGION=us-east-1
#   add_my_var MY_REGION
#   recall

resolve_recall_file() {
  # Simple default: allow override via RECALL_STATE_FILE env, otherwise use $HOME
  echo "${RECALL_STATE_FILE:-$HOME/RECALL_MY_STATE}"
}

# _ensure_recall_file: internal helper to check and create recall file if needed
_ensure_recall_file() {
  local path
  path=$(resolve_recall_file)
  if [[ ! -f "$path" ]]; then
    init_recall || return 1
  fi
  return 0
}

# init_recall: create the recall file with a marker and a header
# Usage: init_recall
init_recall() {
  local path
  path=$(resolve_recall_file)

  mkdir -p "$(dirname "$path")"
  # If file already exists, don't overwrite it
  if [[ -f "$path" ]]; then
    # ensure rc block is installed, then return
      # Add sourcing block to bash rc so the helpers are available at login
      add_rc_source_block "$HOME/.bashrc" >/dev/null 2>&1 || true
    return 0
  fi

  cat > "$path" <<'EOF'
# This file remembers your current values/state in the workshop
### END OF MY STATE ###
EOF
  chmod 644 "$path"
  # Add sourcing block to bash rc so the helpers are available at login
  add_rc_source_block "$HOME/.bashrc" >/dev/null 2>&1 || true
  return 0
}

# add sourcing block to user's rc file with scp guard
add_rc_source_block() {
  local rcfile="$1"
  local marker_start="# {recall_state} BEGIN"
  local marker_end="# {recall_state} END"
  if [[ -z "$rcfile" ]]; then return 0; fi
  # create rc file if missing
  if [[ ! -f "$rcfile" ]]; then
    touch "$rcfile" || return 1
  fi
  # don't duplicate
  if grep -Fq "$marker_start" "$rcfile" 2>/dev/null; then
    return 0
  fi
  cat >> "$rcfile" <<'EOF'
# {recall_state} BEGIN
# Skip rc entirely when this is an scp session
#if [[ -n "$SSH_CONNECTION" && -z "$SSH_TTY" ]]; then
if [[ "$SSH_ORIGINAL_COMMAND" =~ ^(scp|sftp-server) ]]; then
  return
fi
if [[ -f "$HOME/project-mountpoint/bin/recall_state.sh" ]]; then
  # source helpers first so resolve_recall_file is available
  source "$HOME/project-mountpoint/bin/recall_state.sh"
  # then source the recall file if present
  if command -v resolve_recall_file >/dev/null 2>&1; then
    _recall_file=$(resolve_recall_file)
    if [[ -n "$_recall_file" && -f "$_recall_file" ]]; then
      source "$_recall_file"
    fi
    unset _recall_file
  fi
fi
# {recall_state} END
EOF
  return 0
}

# add_my_var: add or update an exported variable in the recall file
# Usage: add_my_var NAME
add_my_var() {
  local name="$1" file val export_line tmp marker='### END OF MY STATE ###'
  if [[ -z "$name" ]]; then return 2; fi
  # capture current environment value of the named variable
  val="${!name}"
  if [[ -z "$val" ]]; then
    echo "Variable '$name' not set in environment" >&2
    return 2
  fi

  _ensure_recall_file || { echo "Failed to create recall file" >&2; return 1; }
  file=$(resolve_recall_file)

  # use printf %q to create a shell-safe representation
  export_line="export $name=$(printf '%q' "$val")"

  tmp=$(mktemp) || { echo "Failed to create temp file" >&2; return 1; }
  awk -v nm="$name" -v aline="$export_line" -v mrk="$marker" '
  BEGIN{replaced=0; pattern="^export[[:space:]]+"nm"="}
  {
    if ($0 ~ pattern) next
    if ($0==mrk && !replaced) { print aline; replaced=1 }
    print $0
  }
  END{ if (!replaced) print aline }' "$file" > "$tmp" || { rm -f "$tmp"; echo "Failed writing variable" >&2; return 1; }

  mv "$tmp" "$file" || { rm -f "$tmp"; echo "Failed saving variable" >&2; return 1; }
  chmod 644 "$file"
  return 0
}

# add_my_alias: add or update an alias definition in the recall file
# Usage: add_my_alias NAME
add_my_alias() {
  local name="$1" file alias_out alias_line tmp marker='### END OF MY STATE ###'
  if [[ -z "$name" ]]; then return 2; fi

  # Only capture aliases that are already defined in the current shell
  alias_out=$(alias "$name" 2>/dev/null || true)
  if [[ -n "$alias_out" ]]; then
    alias_line="$alias_out"
  else
    echo "Alias '$name' not found in current shell" >&2
    return 2
  fi

  _ensure_recall_file || { echo "Failed to create recall file" >&2; return 1; }
  file=$(resolve_recall_file)

  tmp=$(mktemp) || { echo "Failed to create temp file" >&2; return 1; }
  awk -v nm="$name" -v aline="$alias_line" -v mrk="$marker" '
  BEGIN{replaced=0; pattern="^alias[[:space:]]+"nm"="}
  {
    if ($0 ~ pattern) next
    if ($0==mrk && !replaced) { print aline; replaced=1 }
    print $0
  }
  END{ if (!replaced) print aline }' "$file" > "$tmp" || { rm -f "$tmp"; echo "Failed writing alias" >&2; return 1; }

  mv "$tmp" "$file" || { rm -f "$tmp"; echo "Failed saving alias" >&2; return 1; }
  chmod 644 "$file"
  return 0
}

# recall: show MY_ variables from environment or from the recall file
# Usage: recall
recall() {
  local file
  file=$(resolve_recall_file)
  
  # Source the recall file first to ensure all exports and aliases are available
  if [[ -f "$file" ]]; then
    source "$file" 2>/dev/null || true
  fi
  
  # prefer environment MY_ variables first
  local state
  state=$(env | grep -E "^MY_" | sort || true)
  if [[ -n "$state" ]]; then
    echo -e "\nRecalled current workshop state:\n---"
    echo "$state"
    echo -e "---\n"
  fi

  # Always show saved aliases from the recall file if present
  if [[ -f "$file" ]]; then
    local aliases
    aliases=$(grep '^alias ' "$file" || true)
    if [[ -n "$aliases" ]]; then
      echo -e "Saved aliases:\n---"
      echo "$aliases"
      echo -e "---\n"
    fi

    # If we didn't print environment variables, fall back to showing saved MY_ exports
    if [[ -z "$state" ]]; then
      local file_state
      file_state=$(grep '^export MY_' "$file" | sed 's/^export //' | sort || true)
      if [[ -n "$file_state" ]]; then
        echo -e "\nRecalled current workshop state (from file):\n---"
        echo "$file_state"
        echo -e "---\n"
        return 0
      fi
    fi
  fi

  # success if we printed either env state or aliases
  if [[ -n "$state" || -n "$aliases" ]]; then
    return 0
  fi

  return 1
}
