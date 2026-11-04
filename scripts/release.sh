#!/bin/sh
# Writes CHANGELOG.md's section for a new version from the "## Changelog"
# sections of the PRs merged since the last release, then commits and tags it.
# Usage: scripts/release.sh <version>, then review and
#   git push origin main v<version>
set -eu
cd "$(dirname "$0")/.."
v=${1:?usage: scripts/release.sh <version>}
[ "$(git branch --show-current)" = main ] || { echo "run on main" >&2; exit 1; }
git diff --quiet HEAD || { echo "commit or stash changes first" >&2; exit 1; }

last=$(git tag --sort=-v:refname | grep -v -- - | head -1)
since=$(TZ=UTC git log -1 --date=format-local:%Y-%m-%dT%H:%M:%SZ --format=%cd "$last")

notes=$(gh pr list --state merged --base main --limit 200 --json mergedAt,body \
  --jq ".[] | select(.mergedAt > \"$since\") | .body" | tr -d '\r' | awk '
  /^## /       { on = ($0 ~ /^## Changelog/); next }
  !on          { next }
  /^### /      { cat = $2; next }
  /^- +[^ ]/   { if (cat) { n[cat]++; item[cat, n[cat]] = $0; cur = 1 }; next }
  /^ +[^ ]/    { if (cur) item[cat, n[cat]] = item[cat, n[cat]] "\n" $0; next }
  END {
    split("Added Changed Fixed", C, " ")
    for (k = 1; k <= 3; k++) {
      c = C[k]; if (!n[c]) continue
      printf "%s### %s\n\n", sep, c; sep = "\n"
      for (j = 1; j <= n[c]; j++) print item[c, j]
    }
  }')
[ -n "$notes" ] || { echo "no changelog entries in PRs merged since $last" >&2; exit 1; }

line=$(grep -n -m1 '^## ' CHANGELOG.md | cut -d: -f1)
{
  head -n $((line - 1)) CHANGELOG.md
  printf '## %s (%s)\n\n%s\n\n' "$v" "$(date +%F)" "$notes"
  tail -n +"$line" CHANGELOG.md
} > CHANGELOG.md.new
mv CHANGELOG.md.new CHANGELOG.md

git add CHANGELOG.md
git commit -q -m "Release $v"
git tag "v$v"
git show --stat HEAD | tail -3
echo "tagged v$v. Review, then: git push origin main v$v"
