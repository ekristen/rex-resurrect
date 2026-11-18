#!/bin/sh
# Install or remove rex-resurrect.
#
#   ./install.sh              copy resurrect.lua into the Rex config directory,
#                             add it to init.lua, and reload the configuration.
#                             Run it again to update.
#   ./install.sh --uninstall  undo that and stop the tracker
#
# It also runs without a checkout, in which case it downloads resurrect.lua:
#
#   curl -fsSL https://raw.githubusercontent.com/ekristen/rex-resurrect/main/install.sh | sh
#   curl -fsSL https://raw.githubusercontent.com/ekristen/rex-resurrect/main/install.sh | sh -s -- --uninstall
#
# REX_RESURRECT_REF picks the branch or tag to download (default: main).
set -eu

url=https://raw.githubusercontent.com/ekristen/rex-resurrect/${REX_RESURRECT_REF:-main}/resurrect.lua

# The directory of this script when it is run from a checkout; empty when it
# is piped into sh.
here=
case $0 in
  */install.sh|install.sh)
    dir=$(cd "$(dirname "$0")" && pwd)
    if [ -f "$dir/resurrect.lua" ]; then here=$dir; fi
    ;;
esac
line='require("resurrect").setup{}'

if [ -n "${REX_CONFIG:-}" ]; then
  init=$REX_CONFIG
else
  init=${XDG_CONFIG_HOME:-$HOME/.config}/rex/init.lua
fi
config_dir=$(dirname "$init")
dest=$config_dir/resurrect.lua

# rex is on PATH in panes Rex creates, but not always elsewhere.
find_rex() {
  if command -v rex >/dev/null 2>&1; then
    command -v rex
    return
  fi
  for app in "/Applications/Rex.app" "/Applications/Rex Beta.app" \
             "$HOME/Applications/Rex.app" "$HOME/Applications/Rex Beta.app"; do
    bin="$app/Contents/Helpers/Rex Server.rex/Contents/MacOS/rex"
    if [ -x "$bin" ]; then
      echo "$bin"
      return
    fi
  done
  return 1
}

rex=$(find_rex) || rex=

if [ "${1:-}" = "--uninstall" ]; then
  if [ -n "$rex" ] && [ -f "$dest" ]; then
    "$rex" --autostart=false do "$dest" cmd=stop || true
  fi
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    rm -f "$dest"
    echo "removed $dest"
  fi
  if [ -f "$init" ] && grep -qF "$line" "$init"; then
    grep -vF "$line" "$init" > "$init.tmp" || true
    mv -f "$init.tmp" "$init"
    echo "removed rex-resurrect from $init"
  fi
  if [ -n "$rex" ]; then
    "$rex" --autostart=false config reload >/dev/null || true
  fi
  echo "State is kept in ${XDG_STATE_HOME:-$HOME/.local/state}/rex-resurrect. Delete it if you no longer want it."
  exit 0
fi

if [ -n "${1:-}" ]; then
  echo "usage: $0 [--uninstall]" >&2
  exit 2
fi

mkdir -p "$config_dir"

# Write to a temporary file first, so that a failed download leaves the
# installed copy alone, and so that a symlink left by an older install is
# replaced rather than written through.
tmp=$dest.tmp.$$
trap 'rm -f "$tmp"' EXIT
rm -f "$tmp"
if [ -n "$here" ]; then
  cp "$here/resurrect.lua" "$tmp"
  from=$here/resurrect.lua
else
  if ! command -v curl >/dev/null 2>&1; then
    echo "curl is needed to download resurrect.lua" >&2
    exit 1
  fi
  curl -fsSL "$url" -o "$tmp"
  from=$url
fi
if ! grep -q 'rex-resurrect' "$tmp"; then
  echo "$from does not look like resurrect.lua; nothing installed" >&2
  exit 1
fi
rm -f "$dest"
mv -f "$tmp" "$dest"
echo "installed $from as $dest"

if [ -f "$init" ] && grep -qF 'require("resurrect")' "$init"; then
  echo "$init already loads rex-resurrect"
else
  printf '%s\n' "$line" >> "$init"
  echo "added rex-resurrect to $init"
fi

if [ -z "$rex" ]; then
  echo "Could not find the rex binary. Run 'rex config reload' from a Rex pane to finish."
  exit 0
fi

"$rex" config check "$init"
"$rex" config reload
# A tracker from an earlier install keeps running the old code until it is
# replaced.
"$rex" do resurrect_restart >/dev/null || true
echo "Installed. The tracker starts in a few seconds; check it with:"
echo "  \"$rex\" do resurrect_status"
