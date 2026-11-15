#!/usr/bin/env bash
# helpoupou installer.
#
#   From a clone:   ./install.sh        (this checkout becomes the install)
#   One-liner:      curl -fsSL https://raw.githubusercontent.com/elopin42/helpoupou/main/install.sh | bash
#
# Either way the result is a `helpoupou` command in ~/.local/bin pointing at a
# git checkout, so `helpoupou self-update` is a plain `git pull`.
set -euo pipefail

REPO_URL=${HELPOUPOU_REPO_URL:-https://github.com/elopin42/helpoupou.git}
TARGET=${HELPOUPOU_INSTALL_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/helpoupou}
BIN_DIR=${HELPOUPOU_BIN_DIR:-$HOME/.local/bin}

here=''
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fi

if [ -n "$here" ] && [ -x "$here/bin/helpoupou" ]; then
  root=$here
  echo "→ using this checkout: $root"
else
  command -v git >/dev/null 2>&1 || {
    echo "✗ git is required to install helpoupou" >&2
    exit 1
  }
  if [ -d "$TARGET/.git" ]; then
    echo "→ updating $TARGET"
    git -C "$TARGET" pull --ff-only
  else
    echo "→ cloning into $TARGET"
    mkdir -p "$(dirname "$TARGET")"
    git clone --depth 1 "$REPO_URL" "$TARGET"
  fi
  root=$TARGET
fi

mkdir -p "$BIN_DIR"
ln -sfn "$root/bin/helpoupou" "$BIN_DIR/helpoupou"
echo "✔ installed: $BIN_DIR/helpoupou -> $root/bin/helpoupou"

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "⚠ $BIN_DIR is not in your PATH. Add it to your shell profile, e.g.: export PATH=\"$BIN_DIR:\$PATH\"" ;;
esac

for tool in docker curl openssl; do
  command -v "$tool" >/dev/null 2>&1 || echo "⚠ $tool is not installed: helpoupou needs it"
done

echo
echo "Next: go to a Docker Compose project and run:  helpoupou init"
