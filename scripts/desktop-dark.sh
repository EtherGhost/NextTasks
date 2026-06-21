#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"

mkdir -p .clickable
desktop_env_file=".clickable/nexttasks-desktop-env.local"
cleanup() {
    rm -f "$desktop_env_file"
}
trap cleanup EXIT

printf 'NEXTTASKS_DESKTOP_DARK_MODE="1"\n' > "$desktop_env_file"
chmod 600 "$desktop_env_file"

~/.local/bin/clickable desktop --arch amd64
