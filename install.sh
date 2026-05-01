#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${1:-$HOME/bin}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$INSTALL_DIR"
cp "$SCRIPT_DIR/skill-manager" "$INSTALL_DIR/skill-manager"
chmod +x "$INSTALL_DIR/skill-manager"

echo "✓ skill-manager installed to $INSTALL_DIR/skill-manager"

if ! echo "$PATH" | tr ':' '\n' | grep -qx "$INSTALL_DIR"; then
  echo ""
  echo "  '$INSTALL_DIR' is not in your PATH. Add it:"
  echo ""
  if [[ -n "${ZSH_VERSION:-}" || "$SHELL" == */zsh ]]; then
    echo "    echo 'export PATH=\"\$HOME/bin:\$PATH\"' >> ~/.zshrc && source ~/.zshrc"
  else
    echo "    echo 'export PATH=\"\$HOME/bin:\$PATH\"' >> ~/.bashrc && source ~/.bashrc"
  fi
  echo ""
fi
