#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"${LUA:-lua}" "$script_dir/smoke/runtime.lua"
"${LUA:-lua}" "$script_dir/smoke/qb_compat.lua"
"${LUA:-lua}" "$script_dir/smoke/ox_compat.lua"
"${LUA:-lua}" "$script_dir/smoke/ox_target_stub.lua"
(cd "$script_dir/.." && "${LUA:-lua}" test/no_raw_print.lua)
