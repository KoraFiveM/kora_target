#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"${LUA:-lua}" "$script_dir/smoke/runtime.lua"
