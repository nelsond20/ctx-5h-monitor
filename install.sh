#!/bin/sh
set -e

INSTALL_DIR="$HOME/.claude"
SCRIPT_NAME="ctx-status.sh"
ALIAS_NAME="ctx"

echo "Installing ctx-5h-monitor..."

# Copy CLI script
cp "$SCRIPT_NAME" "$INSTALL_DIR/$SCRIPT_NAME"
chmod +x "$INSTALL_DIR/$SCRIPT_NAME"
echo "  Copied $SCRIPT_NAME to $INSTALL_DIR/"

# Add alias to shell RC if not already present
if [ -n "$ZSH_VERSION" ] || [ "$(basename "$SHELL")" = "zsh" ]; then
  RC_FILE="$HOME/.zshrc"
else
  RC_FILE="$HOME/.bashrc"
fi

ALIAS_LINE="alias $ALIAS_NAME='$INSTALL_DIR/$SCRIPT_NAME'"

if grep -qF "$ALIAS_LINE" "$RC_FILE" 2>/dev/null; then
  echo "  Alias '$ALIAS_NAME' already exists in $RC_FILE — skipping"
else
  printf '\n%s\n' "$ALIAS_LINE" >> "$RC_FILE"
  echo "  Added alias '$ALIAS_NAME' to $RC_FILE"
fi

echo ""
echo "Done. Reload your shell to use 'ctx':"
echo "  source $RC_FILE"
echo ""
echo "For statusline integration, see statusline/patch.sh"
