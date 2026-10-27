#!/usr/bin/env bash
# Builds the web export and publishes it to the repo's gh-pages branch (GitHub Pages), served at
# revengeofthepaws.com. Run from anywhere: tools/deploy_web.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOMAIN="revengeofthepaws.com"
GODOT="${GODOT:-$(command -v godot || ls /c/Users/*/AppData/Local/Microsoft/WinGet/Packages/GodotEngine*/Godot_v*_console.exe | head -1)}"

cd "$ROOT"
mkdir -p build/web
"$GODOT" --headless --path "$ROOT" --export-release "Web" build/web/index.html

# Publish build/web as the only content of gh-pages, in a throwaway work tree.
SITE="$(mktemp -d)"
trap 'git -C "$ROOT" worktree remove --force "$SITE" 2>/dev/null || rm -rf "$SITE"' EXIT
git fetch origin gh-pages 2>/dev/null || true
if git show-ref --verify --quiet refs/remotes/origin/gh-pages; then
	git worktree add -B gh-pages "$SITE" origin/gh-pages
else
	git worktree add --detach "$SITE"
	git -C "$SITE" checkout --orphan gh-pages
fi
git -C "$SITE" rm -rf --quiet . 2>/dev/null || true
cp -r build/web/. "$SITE"/
echo "$DOMAIN" > "$SITE/CNAME"
touch "$SITE/.nojekyll"
git -C "$SITE" add -A
if git -C "$SITE" diff --cached --quiet; then
	echo "Nothing changed; site is up to date."
	exit 0
fi
git -C "$SITE" commit -m "Deploy web build from $(git rev-parse --short HEAD)"
git -C "$SITE" push origin gh-pages
echo "Deployed: https://$DOMAIN"
