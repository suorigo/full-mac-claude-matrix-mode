#!/bin/zsh
# Removes Matrix mode and everything install.sh added.
PREFIX="$HOME/.matrix-mode"
AGENT="dev.claude-matrix-mode.hotkey"
MARK="# claude-matrix-mode"

osascript -e 'tell application id "dev.claude-matrix-mode.app" to quit' >/dev/null 2>&1
sleep 2
[[ -x "$PREFIX/matrix" && "$("$PREFIX/matrix" status)" == on ]] && "$PREFIX/matrix" off

for a in $AGENT dev.claude-matrix-mode.sweep; do
  launchctl bootout "gui/$(id -u)/$a" 2>/dev/null
  rm -f "$HOME/Library/LaunchAgents/$a.plist"
done
[[ "$(defaults read "$HOME/Applications/Matrix.app/Contents/Info" CFBundleIdentifier 2>/dev/null)" == dev.claude-matrix-mode.app ]] \
  && rm -rf "$HOME/Applications/Matrix.app"
rm -rf "$PREFIX" "$HOME/.cache/matrix-mode"
rm -f "$HOME/.config/ghostty/matrix-mode.conf"

# the marker line plus the exact line install.sh wrote after it (leave anything else alone)
for f in "$HOME/.config/ghostty/config" "$HOME/.tmux.conf"; do
  [[ -f "$f" ]] && /usr/bin/python3 - "$f" "$MARK" <<'EOF'
import sys
path, mark = sys.argv[1], sys.argv[2]
ours = ('config-file = ?', 'set -g allow-passthrough on')
lines = open(path).readlines()
out, i = [], 0
while i < len(lines):
    if lines[i].startswith(mark):
        if i + 1 < len(lines) and lines[i + 1].startswith(ours) and ('matrix-mode.conf' in lines[i + 1] or 'passthrough' in lines[i + 1]):
            i += 1
        i += 1
        continue
    out.append(lines[i]); i += 1
open(path, 'w').write(''.join(out))
EOF
done

/usr/bin/python3 - <<'EOF'
import json, os
p = os.path.realpath(os.path.expanduser('~/.claude/settings.json'))
if os.path.exists(p):
    mode = os.stat(p).st_mode & 0o777
    d = json.load(open(p))
    for ev, groups in list(d.get('hooks', {}).items()):
        groups = [g for g in groups if not any('matrix-state' in h.get('command', '') for h in g.get('hooks', []))]
        if groups: d['hooks'][ev] = groups
        else: del d['hooks'][ev]
    tmp = p + '.tmp'
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, mode)
    with os.fdopen(fd, 'w') as f:
        json.dump(d, f, indent=2, ensure_ascii=False)
    os.chmod(tmp, mode)
    os.replace(tmp, p)
EOF

echo "Matrix mode removed. Your settings in ~/.config/matrix-mode were kept (delete them by hand if you like)."
