#!/bin/zsh
# Installs Matrix mode for Ghostty + Claude Code.
#   ./install.sh                 build and install everything
#   ./install.sh --via-ssh       run window control through `ssh localhost` (see README)
#   ./install.sh --no-hotkey     skip the global toggle key
#   ./install.sh --tmux          also enable tmux passthrough (needed for the working signal inside tmux, see README)
set -e
cd "${0:A:h}"
SRC="$PWD"
PREFIX="$HOME/.matrix-mode"
APP="$HOME/Applications/Matrix.app"
CFG_DIR="$HOME/.config/matrix-mode"
GHOSTTY_DIR="$HOME/.config/ghostty"
AGENT="dev.claude-matrix-mode.hotkey"
PLIST="$HOME/Library/LaunchAgents/$AGENT.plist"
MARK="# claude-matrix-mode"

via_ssh=0; hotkey=1; tmux_pt=0
for a in "$@"; do
  case "$a" in
    --via-ssh) via_ssh=1 ;;
    --no-hotkey) hotkey=0 ;;
    --tmux) tmux_pt=1 ;;
    *) echo "unknown option $a"; exit 1 ;;
  esac
done

say() { print -P "%F{green}▸%f $*"; }

[[ "$(uname)" == Darwin ]] || { echo "macOS only"; exit 1; }
[[ -d /Applications/Ghostty.app ]] || echo "warning: Ghostty not found in /Applications (https://ghostty.org)"
command -v swiftc >/dev/null || { echo "swiftc missing, run: xcode-select --install"; exit 1; }

say "building"
mkdir -p build
swiftc -O src/tile.swift -o build/matrix-tile
swiftc -O src/hotkey.swift -o build/matrix-hotkey
swiftc -O src/keycode.swift -o build/matrix-keycode
swiftc -O src/MatrixApp.swift -o build/Matrix

say "installing to $PREFIX"
mkdir -p "$PREFIX"
# remove first: overwriting a running binary in place makes macOS kill the new copy (code signature mismatch)
rm -f "$PREFIX"/matrix-tile "$PREFIX"/matrix-hotkey "$PREFIX"/matrix-keycode
cp scripts/matrix scripts/matrix-state shaders/matrix.glsl config/ghostty-matrix.conf \
   build/matrix-tile build/matrix-hotkey build/matrix-keycode "$PREFIX/"
chmod +x "$PREFIX/matrix" "$PREFIX/matrix-state"

say "installing $APP"
osascript -e 'tell application id "dev.claude-matrix-mode.app" to quit' >/dev/null 2>&1 || true
if [[ -d "$APP" ]]; then   # never delete somebody else's Matrix.app
  [[ "$(defaults read "$APP/Contents/Info" CFBundleIdentifier 2>/dev/null)" == dev.claude-matrix-mode.app ]] \
    || { echo "$APP exists and is not ours, move it away first"; exit 1; }
  rm -rf "$APP"
fi
mkdir -p "$APP/Contents/MacOS"
cp build/Matrix "$APP/Contents/MacOS/Matrix"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Matrix</string>
<key>CFBundleIdentifier</key><string>dev.claude-matrix-mode.app</string>
<key>CFBundleExecutable</key><string>Matrix</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
EOF
codesign -s - --force "$APP" >/dev/null 2>&1 || true

say "config in $CFG_DIR"
mkdir -p "$CFG_DIR"
[[ -f "$CFG_DIR/config" ]] || cp config/config.example "$CFG_DIR/config"
if (( via_ssh )); then
  grep -q '^via_ssh=' "$CFG_DIR/config" && sed -i '' 's/^via_ssh=.*/via_ssh=1/' "$CFG_DIR/config" || echo "via_ssh=1" >> "$CFG_DIR/config"
fi

say "Ghostty theme include"
mkdir -p "$GHOSTTY_DIR"
touch "$GHOSTTY_DIR/config" "$GHOSTTY_DIR/matrix-mode.conf"
grep -q "matrix-mode.conf" "$GHOSTTY_DIR/config" || \
  printf '\n%s (empty unless Matrix mode is on)\nconfig-file = ?%s\n' "$MARK" "$GHOSTTY_DIR/matrix-mode.conf" >> "$GHOSTTY_DIR/config"

say "Claude Code hooks"
mkdir -p "$HOME/.claude"
/usr/bin/python3 - "$PREFIX/matrix-state" <<'EOF'
import json, os, shlex, shutil, sys
state = shlex.quote(sys.argv[1])
p = os.path.realpath(os.path.expanduser('~/.claude/settings.json'))   # follow a symlinked settings file
d = json.load(open(p)) if os.path.exists(p) else {}
hooks = d.setdefault('hooks', {})
# drop entries from older versions, then add one "hook" entry per event
for ev, groups in list(hooks.items()):
    hooks[ev] = [g for g in groups if not any('matrix-state' in h.get('command', '') for h in g.get('hooks', []))]
for ev in ['SessionStart', 'UserPromptSubmit', 'PreToolUse', 'Notification', 'Stop',
           'SubagentStart', 'SubagentStop', 'TaskCreated', 'TaskCompleted']:
    hooks.setdefault(ev, []).append({'hooks': [{'type': 'command', 'command': f'{state} hook', 'timeout': 5}]})
for ev in [e for e, g in hooks.items() if not g]:
    del hooks[ev]
if os.path.exists(p):
    shutil.copy2(p, p + '.before-matrix-mode')   # backup
    mode = os.stat(p).st_mode & 0o777
else:
    mode = 0o600
tmp = p + '.tmp'
fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, mode)
with os.fdopen(fd, 'w') as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
os.chmod(tmp, mode)
os.replace(tmp, p)
EOF

if (( tmux_pt )) && command -v tmux >/dev/null; then
  say "tmux passthrough (so the hook signal reaches Ghostty from inside tmux)"
  touch "$HOME/.tmux.conf"
  grep -q "allow-passthrough on" "$HOME/.tmux.conf" || printf '\n%s\nset -g allow-passthrough on\n' "$MARK" >> "$HOME/.tmux.conf"
  tmux set -g allow-passthrough on 2>/dev/null || true
fi

if (( hotkey )); then
  say "toggle key (LaunchAgent $AGENT)"
  if (( via_ssh )); then
    args="<string>/usr/bin/ssh</string><string>-n</string><string>-o</string><string>BatchMode=yes</string><string>-o</string><string>ServerAliveInterval=30</string><string>localhost</string><string>$PREFIX/matrix-hotkey</string>"
  else
    args="<string>$PREFIX/matrix-hotkey</string>"
  fi
  mkdir -p "${PLIST:h}"
  cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$AGENT</string>
<key>ProgramArguments</key><array>$args</array>
<key>RunAtLoad</key><true/>
<key>KeepAlive</key><true/>
<key>ThrottleInterval</key><integer>10</integer>
<key>StandardErrorPath</key><string>$HOME/Library/Logs/matrix-hotkey.log</string>
</dict></plist>
EOF
  launchctl bootout "gui/$(id -u)/$AGENT" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$PLIST"
fi

echo
say "done. Start it with:  open ~/Applications/Matrix.app"
(( hotkey )) && say "or press the toggle key (default ctrl+alt+cmd+M, change it in $CFG_DIR/config)"
command -v tmux >/dev/null && (( ! tmux_pt )) && echo "  tmux users: re-run with --tmux to get the working signal inside tmux (see README)."
echo "  macOS will ask for Accessibility (Matrix.app) and Input Monitoring (matrix-hotkey) on first use."
echo "  Optional: ln -s $PREFIX/matrix /usr/local/bin/matrix   →   matrix on | off | tile | status"
