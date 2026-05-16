#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$SCRIPT_DIR/.local"
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage:
  ./clean-local-node-files.sh [--dry-run] [base_dir]

In each node* directory under base_dir, removes every file and directory
except:
  - bsc.log.* (rotated bsc logs), e.g. bsc.log.2026-05-04_17
  - bsc-node.log and bsc-node.log.* (node log and its rotations)

Deletes:
  - Everything else at the top level of each node* (including geth/, geth.ipc,
    bsc.log, geth executables, etc.)

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
    if [[ -d "$path" && ! -L "$path" ]]; then
      printf '[dry-run] would remove dir %s\n' "$path"
    else
      printf '[dry-run] would remove %s\n' "$path"
    fi
  else
    rm -rf -- "$path"
    printf 'removed %s\n' "$path"
  fi
}

removed=0
shopt -s nullglob dotglob

for node_dir in "$BASE_DIR"/node*/; do
  [[ -d "$node_dir" ]] || continue

  for path in "$node_dir"/*; do
    [[ -e "$path" || -L "$path" ]] || continue
    base="$(basename "$path")"
    if [[ "$base" == bsc.log.* || "$base" == bsc-node.log || "$base" == bsc-node.log.* ]]; then
      continue
    fi
    delete_path "$path"
    removed=$((removed + 1))
  done
done

if [[ "$DRY_RUN" -eq 1 ]]; then
  printf '[dry-run] total matched: %d\n' "$removed"
else
  printf 'total removed: %d\n' "$removed"
fi
