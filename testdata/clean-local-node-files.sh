#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$SCRIPT_DIR/.local"
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage:
  ./clean-local-node-files.sh [--dry-run] [base_dir]

Deletes from each node* directory under base_dir:
  - geth.ipc
  - bsc.log
  - top-level geth executable files like geth0, geth1, geth2

Keeps:
  - bsc.log.* files, e.g. bsc.log.2026-05-04_17
  - geth/ data directories

Default base_dir: testdata/.local
EOF
}

while (($#)); do
  case "$1" in
    --dry-run|-n)
      DRY_RUN=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      BASE_DIR="$1"
      shift
      ;;
  esac
done

if [[ ! -d "$BASE_DIR" ]]; then
  echo "Base directory does not exist: $BASE_DIR" >&2
  exit 1
fi

delete_path() {
  local path="$1"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '[dry-run] would remove %s\n' "$path"
  else
    rm -f -- "$path"
    printf 'removed %s\n' "$path"
  fi
}

removed=0
shopt -s nullglob

for node_dir in "$BASE_DIR"/node*/; do
  [[ -d "$node_dir" ]] || continue

  for name in geth.ipc bsc.log; do
    path="$node_dir$name"
    if [[ -e "$path" || -L "$path" ]]; then
      delete_path "$path"
      removed=$((removed + 1))
    fi
  done

  for path in "$node_dir"/geth*; do
    [[ -f "$path" ]] || continue
    [[ "$(basename "$path")" == "geth.ipc" ]] && continue
    delete_path "$path"
    removed=$((removed + 1))
  done
done

if [[ "$DRY_RUN" -eq 1 ]]; then
  printf '[dry-run] total matched: %d\n' "$removed"
else
  printf 'total removed: %d\n' "$removed"
fi
