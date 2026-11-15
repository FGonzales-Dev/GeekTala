#!/bin/bash
# Exports every Apple Notes note to a folder of Markdown files that Noote's
# Import Folder… brings in (see README.md).
#
#   tools/apple-notes-export/export.sh [--replace] [DEST]
#
# DEST defaults to ~/Documents/Apple Notes. An existing DEST is only
# replaced with --replace. Prints counts only, never note contents.
set -euo pipefail

replace=false
if [ "${1:-}" = "--replace" ]; then replace=true; shift; fi
dest="${1:-$HOME/Documents/Apple Notes}"
here="$(cd "$(dirname "$0")" && pwd)"

if [ -e "$dest" ] && [ "$replace" != true ]; then
  echo "$dest already exists; use --replace to overwrite it." >&2
  exit 1
fi

work="$(mktemp -d)"
chmod 700 "$work"
# Notes is sandboxed and can only save attachments somewhere like Downloads.
save="$HOME/Downloads/.noote-apple-notes-export"
trap 'rm -rf "$work" "$save"' EXIT
rm -rf "$save"
mkdir -p "$save"

SAVE_DIR="$save" osascript -l JavaScript "$here/dump_notes.js" > "$work/notes.json"
python3 -I "$here/to_markdown.py" "$work/notes.json" "$work/out"

if [ -e "$dest" ]; then rm -rf "$dest"; fi
mkdir -p "$(dirname "$dest")"
mv "$work/out" "$dest"
echo "Exported to $dest"
