#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"

mkdir -p .clickable

env_source=""
for candidate in ".env.test.local" "../NextNews/.env.test.local" "../NextNotes/.env.test.local"; do
    if [[ -f "$candidate" ]]; then
        env_source="$candidate"
        break
    fi
done

if [[ -z "$env_source" ]]; then
    echo "Missing test credentials. Create .env.test.local or keep the existing NextNews/NextNotes test env files available." >&2
    exit 1
fi

tmp_config="$(mktemp .clickable/nexttasks-desktop-test.XXXXXX.yaml)"
desktop_env_file=".clickable/nexttasks-desktop-env.local"
cleanup() {
    rm -f "$tmp_config"
    rm -f "$desktop_env_file"
}
trap cleanup EXIT

python3 - "$env_source" "$tmp_config" "$desktop_env_file" <<'INNERPY'
import pathlib
import os
import sys

env_path = pathlib.Path(sys.argv[1])
config_path = pathlib.Path(sys.argv[2])
desktop_env_path = pathlib.Path(sys.argv[3])
project_config = pathlib.Path("clickable.yaml").read_text(encoding="utf-8")

def parse_env(path):
    values = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip().strip('"').strip("'")
    return values

values = parse_env(env_path)

def first(*keys):
    for key in keys:
        value = values.get(key, "").strip()
        if value:
            return value
    return ""

mapped = {
    "NEXTTASKS_DESKTOP_DARK_MODE": os.environ.get("NEXTTASKS_DESKTOP_DARK_MODE", "1"),
    "NEXTTASKS_DESKTOP_TEST_AUTH": "1",
    "NEXTTASKS_TEST_SERVER": first("NEXTTASKS_TEST_SERVER", "NEXTCLOUD_TEST_SERVER", "NEXTNEWS_TEST_SERVER", "NEXTNOTES_TEST_SERVER"),
    "NEXTTASKS_TEST_USERNAME": first("NEXTTASKS_TEST_USERNAME", "NEXTCLOUD_TEST_USERNAME", "NEXTNEWS_TEST_USERNAME", "NEXTNOTES_TEST_USERNAME"),
    "NEXTTASKS_TEST_APP_PASSWORD": first("NEXTTASKS_TEST_APP_PASSWORD", "NEXTCLOUD_TEST_APP_PASSWORD", "NEXTNEWS_TEST_APP_PASSWORD", "NEXTNOTES_TEST_APP_PASSWORD"),
}
missing = [key for key in ["NEXTTASKS_TEST_SERVER", "NEXTTASKS_TEST_USERNAME", "NEXTTASKS_TEST_APP_PASSWORD"] if not mapped[key]]
if missing:
    raise SystemExit("Missing required test env values: " + ", ".join(missing))

with config_path.open("w", encoding="utf-8") as handle:
    handle.write(project_config.rstrip())
    handle.write("\n")
    handle.write("env_vars:\n")
    for key, value in mapped.items():
        handle.write(f"  {key}: {value!r}\n")

with desktop_env_path.open("w", encoding="utf-8") as handle:
    for key, value in mapped.items():
        handle.write(f"{key}={value!r}\n")
INNERPY

chmod 600 "$desktop_env_file"
~/.local/bin/clickable desktop --arch amd64 --config "$tmp_config"
