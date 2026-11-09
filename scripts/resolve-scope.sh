#!/usr/bin/env bash
# resolve-scope.sh - deterministic scope resolution for pr-security-scan.
#
# Usage: resolve-scope.sh --out <dir> [--base <ref>] [--pr <number>]
#
# Scope = everything between the merge-base with the base branch and the current
# working tree (commits + staged + unstaged + untracked), tagged per file as
# committed / uncommitted / both. Writes to <dir>:
#   scope.txt        key=value summary (also printed to stdout)
#   files.tsv        path, status, origin, added, deleted, category
#   diff.patch       merge-base -> working tree (tracked + untracked text files), rename-aware
#   uncommitted.patch  HEAD -> working tree (tracked + untracked text files)
#   renames.tsv      status, old path, new path for every rename or move (R100 = content unchanged)
#   commits.txt      one line per commit on the branch (untrusted text)
#   pr.md            PR title/body when an open PR exists (untrusted text)
set -euo pipefail
export LC_ALL=C

out=""; base_override=""; pr_override=""
while [ $# -gt 0 ]; do
  case "$1" in
    --out)  out="${2:-}"; shift 2 ;;
    --base) base_override="${2:-}"; shift 2 ;;
    --pr)   pr_override="${2:-}"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -n "$out" ] || { echo "--out <dir> is required" >&2; exit 2; }
root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "not a git repository" >&2; exit 2; }
cd "$root"
mkdir -p "$out"

branch=$(git symbolic-ref --short -q HEAD || echo "(detached)")
head_sha=$(git rev-parse HEAD)

resolve_branch() { # branch name -> best ref (prefers origin/<name>), or empty
  if git show-ref -q --verify "refs/remotes/origin/$1"; then echo "origin/$1"
  elif git show-ref -q --verify "refs/heads/$1"; then echo "$1"
  fi
}

default_branch=$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##' || true)
if [ -z "$default_branch" ]; then
  for c in main master develop; do
    if [ -n "$(resolve_branch "$c")" ]; then default_branch=$c; break; fi
  done
fi

# --- Open PR (optional; needs an authenticated gh) -------------------------
pr_number=""; pr_url=""; pr_base=""; pr_head=""; pr_cross=""; pr_state=""; pr_author=""
if command -v gh >/dev/null 2>&1; then
  tsv=$(gh pr view ${pr_override:+"$pr_override"} \
    --json number,url,baseRefName,headRefOid,isCrossRepository,state,author \
    --jq '[.number,.url,.baseRefName,.headRefOid,.isCrossRepository,.state,.author.login]|@tsv' 2>/dev/null || true)
  if [ -n "$tsv" ]; then
    IFS=$'\t' read -r pr_number pr_url pr_base pr_head pr_cross pr_state pr_author <<EOF
$tsv
EOF
    if [ "$pr_state" = "OPEN" ]; then
      gh pr view ${pr_override:+"$pr_override"} --json title,body \
        --jq '"# " + .title + "\n\n" + (.body // "")' > "$out/pr.md" 2>/dev/null || true
    else
      pr_number=""; pr_url=""; pr_base=""
    fi
  fi
fi

# --- Base selection ----------------------------------------------------------
base=""; base_source=""
if [ -n "$base_override" ]; then
  git rev-parse --verify -q "$base_override^{commit}" >/dev/null || { echo "cannot resolve --base $base_override" >&2; exit 2; }
  base=$base_override; base_source="user"
elif [ -n "$pr_base" ] && [ -n "$(resolve_branch "$pr_base")" ]; then
  base=$(resolve_branch "$pr_base"); base_source="pr"
fi
if [ -z "$base" ] && [ "$branch" != "(detached)" ]; then
  # The branch this one was checked out from: branch-creation reflog entry, then
  # the oldest "moving from X to <branch>" HEAD reflog entry.
  from=$(git reflog show "$branch" 2>/dev/null | tail -1 | sed -n 's/.*branch: Created from \(.*\)$/\1/p' || true)
  case "$from" in HEAD|""|*[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) from="" ;; esac
  if [ -z "$from" ]; then
    from=$(git reflog show HEAD 2>/dev/null | grep -E "checkout: moving from .* to $branch\$" | tail -1 \
      | sed -E 's/.*moving from (.*) to .*/\1/' || true)
  fi
  from=${from#origin/}
  if [ -n "$from" ] && [ "$from" != "$branch" ] && [ -n "$(resolve_branch "$from")" ]; then
    base=$(resolve_branch "$from"); base_source="reflog"
  fi
fi
if [ -z "$base" ] && [ -n "$default_branch" ]; then
  base=$(resolve_branch "$default_branch"); base_source="default"
fi
[ -n "$base" ] || { echo "could not determine a base branch; pass --base <ref>" >&2; exit 2; }

merge_base=$(git merge-base "$base" HEAD) || { echo "no merge-base between $base and HEAD" >&2; exit 2; }
commits_ahead=$(git rev-list --count "$merge_base..HEAD")

# --- File sets ---------------------------------------------------------------
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
git diff --no-renames --name-status "$merge_base"            > "$tmp/all.status"
git diff --no-renames --name-only "$merge_base" HEAD         > "$tmp/committed.set"
git diff --no-renames --name-only HEAD                       > "$tmp/uncommitted.set"
git ls-files --others --exclude-standard                     > "$tmp/untracked.set"
cat "$tmp/untracked.set" >> "$tmp/uncommitted.set"
git diff --no-renames --numstat "$merge_base"                > "$tmp/all.numstat"
# Renames and moves: R100 means the content is identical, so it is not review work.
git diff -M --name-status "$merge_base" | awk -F'\t' '/^R/ {print $1 "\t" $2 "\t" $3}' > "$out/renames.tsv"
awk -F'\t' '$1=="R100" {print $2; print $3}' "$out/renames.tsv" > "$tmp/moved.set"
awk -F'\t' '{print $2}' "$out/renames.tsv" > "$tmp/rename_old.set"
awk -F'\t' '$1!="R100" {print $3}' "$out/renames.tsv" > "$tmp/rename_new.set"
renames=$(wc -l < "$out/renames.tsv" | tr -d ' ')
pure_renames=$(awk -F'\t' '$1=="R100"' "$out/renames.tsv" | wc -l | tr -d ' ')

category() {
  case "$1" in
    dist/*|build/*|vendor/*|node_modules/*|*.min.js|*.min.css|*.map|*.snap|*.generated.*|*.pb.go) echo generated ;;
    package-lock.json|*/package-lock.json|yarn.lock|*/yarn.lock|pnpm-lock.yaml|*/pnpm-lock.yaml|poetry.lock|uv.lock|Cargo.lock|go.sum|Gemfile.lock|composer.lock|bun.lockb) echo lock ;;
    .github/workflows/*|.github/actions/*|.gitlab-ci.yml|Jenkinsfile|.circleci/*|azure-pipelines*) echo ci ;;
    Dockerfile*|*/Dockerfile*|docker-compose*|*.tf|*.tfvars|*/charts/*|*/helm/*|*/k8s/*|*/kubernetes/*|serverless.yml|wrangler.toml) echo infra ;;
    package.json|*/package.json|pyproject.toml|requirements*.txt|go.mod|Cargo.toml|Gemfile|pom.xml|build.gradle*|composer.json) echo manifest ;;
    test/*|tests/*|*/test/*|*/tests/*|*/__tests__/*|*/__mocks__/*|*/e2e/*|*.test.*|*.spec.*|*_test.go|*/test_*.py|test_*.py) echo tests ;;
    *.md|*.mdx|*.rst|*.txt|docs/*|*/docs/*|LICENSE*) echo docs ;;
    *) echo code ;;
  esac
}

: > "$out/files.tsv"
total_files=0; reviewable=0; changed_lines=0; uncommitted_files=0
while IFS=$'\t' read -r st path; do
  [ -n "$path" ] || continue
  # The old side of a rename is the same file; only the new path is listed.
  grep -Fxq -- "$path" "$tmp/rename_old.set" && continue
  c=0; u=0
  grep -Fxq -- "$path" "$tmp/committed.set"   && c=1
  grep -Fxq -- "$path" "$tmp/uncommitted.set" && u=1
  origin=committed; [ $u = 1 ] && { origin=uncommitted; [ $c = 1 ] && origin=both; }
  nums=$(awk -F'\t' -v p="$path" '$3==p {print $1"\t"$2; exit}' "$tmp/all.numstat")
  if grep -Fxq -- "$path" "$tmp/rename_new.set"; then
    # A rename with edits: count only the lines that changed, not the whole file twice.
    oldp=$(awk -F'\t' -v n="$path" '$3==n {print $2; exit}' "$out/renames.tsv")
    nums=$(git diff --numstat --no-index -- <(git show "$merge_base:$oldp" 2>/dev/null) "$path" 2>/dev/null | awk '{print $1 "\t" $2; exit}' || true)
    st=R
  fi
  add=${nums%%$'\t'*}; del=${nums##*$'\t'}; add=${add:--}; del=${del:--}
  cat=$(category "$path")
  grep -Fxq -- "$path" "$tmp/moved.set" && cat=moved
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$path" "$st" "$origin" "$add" "$del" "$cat" >> "$out/files.tsv"
done < "$tmp/all.status"

# Untracked files are not in `git diff`; add them as status U (text files <= 1 MiB).
: > "$tmp/untracked.patch"
while IFS= read -r path; do
  [ -n "$path" ] && [ -f "$path" ] || continue
  size=$(wc -c < "$path" | tr -d ' ')
  if [ "$size" -gt 1048576 ] || ! grep -Iq . "$path" 2>/dev/null; then
    printf '%s\tU\tuncommitted\t-\t-\t%s\n' "$path" "$(category "$path")" >> "$out/files.tsv"
    continue
  fi
  lines=$(wc -l < "$path" | tr -d ' ')
  printf '%s\tU\tuncommitted\t%s\t0\t%s\n' "$path" "$lines" "$(category "$path")" >> "$out/files.tsv"
  git diff --no-index --no-renames -U8 -- /dev/null "$path" >> "$tmp/untracked.patch" || true
done < "$tmp/untracked.set"

while IFS=$'\t' read -r path st origin add del cat; do
  total_files=$((total_files+1))
  [ "$origin" != committed ] && uncommitted_files=$((uncommitted_files+1))
  case "$cat" in docs|tests|moved) ;; *)
    reviewable=$((reviewable+1))
    case "$cat" in lock|generated) ;; *)
      [ "$add" != "-" ] && changed_lines=$((changed_lines + add + del)) ;;
    esac ;;
  esac
done < "$out/files.tsv"

{ git diff -M -U8 "$merge_base"; cat "$tmp/untracked.patch"; } > "$out/diff.patch"
{ git diff --no-renames -U8 HEAD;          cat "$tmp/untracked.patch"; } > "$out/uncommitted.patch"
git log --format='%h %s' "$merge_base..HEAD" > "$out/commits.txt"

# Size is judged on reviewable content: pure moves and docs/tests do not count, and a wide
# mechanical sweep (many files, few lines each) is large only if its lines are.
if   [ "$reviewable" -gt 300 ] || [ "$changed_lines" -gt 6000 ]; then size=too_large
elif [ "$reviewable" -gt 150 ] || [ "$changed_lines" -gt 2500 ]; then size=large
elif [ "$changed_lines" -gt 400  ]; then size=medium
else size=small; fi

early_exit=false; reason=""
if [ "$total_files" -eq 0 ]; then early_exit=true; reason="no changes between $base and the working tree"
elif [ "$reviewable" -eq 0 ]; then early_exit=true; reason="only docs/tests changed"; fi

pr_head_matches=""
[ -n "$pr_head" ] && { [ "$pr_head" = "$head_sha" ] && pr_head_matches=true || pr_head_matches=false; }

{
  echo "repo_root=$root"
  echo "branch=$branch"
  echo "head=$head_sha"
  echo "base=$base"
  echo "base_source=$base_source"
  echo "default_branch=$default_branch"
  echo "merge_base=$merge_base"
  echo "commits_ahead=$commits_ahead"
  echo "pr_number=$pr_number"
  echo "pr_url=$pr_url"
  echo "pr_author=$pr_author"
  echo "pr_cross_repo=$pr_cross"
  echo "pr_head_matches_local=$pr_head_matches"
  echo "files_changed=$total_files"
  echo "files_uncommitted=$uncommitted_files"
  echo "files_reviewable=$reviewable"
  echo "renames=$renames"
  echo "pure_renames=$pure_renames"
  echo "changed_lines=$changed_lines"
  echo "size_class=$size"
  echo "early_exit=$early_exit"
  echo "early_exit_reason=$reason"
  echo "out_dir=$out"
} | tee "$out/scope.txt"
