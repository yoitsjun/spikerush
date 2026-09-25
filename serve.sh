#!/usr/bin/env sh
# Live-sync Spike Rush into Roblox Studio.
#   1. Run this script (it starts `rojo serve` on localhost:34872).
#   2. In Studio, open a place (or SpikeRush.rbxlx), open the Rojo plugin and press Connect.
# The Studio plugin must be Rojo 7.7.x; `rojo plugin install` installs the matching one.
cd "$(dirname "$0")" || exit 1
if ! command -v rojo >/dev/null 2>&1; then
	echo "rojo not found. Install the toolchain first: 'rokit install' or 'aftman install'."
	exit 1
fi
rojo --version
exec rojo serve default.project.json "$@"
