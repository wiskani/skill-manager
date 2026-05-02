#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${1:-$HOME/bin}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$INSTALL_DIR"
cp "$SCRIPT_DIR/skill-manager"      "$INSTALL_DIR/skill-manager"
cp "$SCRIPT_DIR/claude-defaults.sh" "$INSTALL_DIR/claude-defaults.sh"
cp "$SCRIPT_DIR/claude-schema.sh"   "$INSTALL_DIR/claude-schema.sh"
chmod +x "$INSTALL_DIR/skill-manager"

echo "✓ skill-manager installed to $INSTALL_DIR/"
echo "  → skill-manager"
echo "  → claude-defaults.sh"
echo "  → claude-schema.sh"

if ! echo "$PATH" | tr ':' '\n' | grep -qx "$INSTALL_DIR"; then
  echo ""
  echo "  '$INSTALL_DIR' is not in your PATH. Add it:"
  echo ""
  if [[ "$SHELL" == */zsh ]]; then
    echo "    echo 'export PATH=\"\$HOME/bin:\$PATH\"' >> ~/.zshrc && source ~/.zshrc"
  else
    echo "    echo 'export PATH=\"\$HOME/bin:\$PATH\"' >> ~/.bashrc && source ~/.bashrc"
  fi
  echo ""
fi
