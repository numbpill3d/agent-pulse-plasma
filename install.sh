#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLASMOID_TARGET="${HOME}/.local/share/plasma/plasmoids/org.scorn.agentpulse"
BIN_TARGET="${HOME}/.local/bin"
SYSTEMD_TARGET="${HOME}/.config/systemd/user/agent-alertd.service"

mkdir -p "$(dirname "$PLASMOID_TARGET")" "$BIN_TARGET" "$(dirname "$SYSTEMD_TARGET")"
ln -sfn "$ROOT" "$PLASMOID_TARGET"
ln -sfn "$ROOT/scripts/agent_alertctl.py" "$BIN_TARGET/agent-alertctl"
ln -sfn "$ROOT/scripts/agent_alertd.py" "$BIN_TARGET/agent-alertd"
install -m 0644 "$ROOT/systemd/agent-alertd.service" "$SYSTEMD_TARGET"

printf 'Installed Agent Pulse widget at %s\n' "$PLASMOID_TARGET"
printf 'Installed CLI and daemon in %s\n' "$BIN_TARGET"
printf 'Wrote user service at %s (not enabled)\n' "$SYSTEMD_TARGET"
printf 'Next: systemctl --user daemon-reload && systemctl --user enable --now agent-alertd.service\n'
