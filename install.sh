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

# Check if INSTALL_DIR is already in PATH
if echo "$PATH" | tr ':' '\n' | grep -qx "$INSTALL_DIR"; then
  echo ""
  echo "✓ $INSTALL_DIR is already in your PATH. All done!"
  exit 0
fi

# Detect shell config file
detect_shell_config() {
  if [[ "$SHELL" == */zsh ]]; then
    echo "$HOME/.zshrc"
  elif [[ "$SHELL" == */bash ]]; then
    if [[ -f "$HOME/.bash_profile" ]]; then
      echo "$HOME/.bash_profile"
    else
      echo "$HOME/.bashrc"
    fi
  else
    echo ""
  fi
}

SHELL_CONFIG=$(detect_shell_config)
PATH_LINE="export PATH=\"\$HOME/bin:\$PATH\""

echo ""
if [[ -n "$SHELL_CONFIG" ]]; then
  echo "  '$INSTALL_DIR' is not in your PATH."
  printf "  Add it automatically to %s? [Y/n]: " "$SHELL_CONFIG"
  read -r answer
  answer="${answer:-Y}"
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    echo "" >> "$SHELL_CONFIG"
    echo "# skill-manager" >> "$SHELL_CONFIG"
    echo "$PATH_LINE" >> "$SHELL_CONFIG"
    echo ""
    echo "✓ Added to $SHELL_CONFIG"
    echo ""
    echo "  Run this to apply in the current session:"
    echo "    source $SHELL_CONFIG"
  else
    echo ""
    echo "  Add manually when ready:"
    echo "    echo '$PATH_LINE' >> $SHELL_CONFIG && source $SHELL_CONFIG"
  fi
else
  echo "  '$INSTALL_DIR' is not in your PATH. Add it manually:"
  echo "    $PATH_LINE"
fi
echo ""
