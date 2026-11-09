#!/usr/bin/env bash
# build-prompt.sh - assemble agent prompt files from the skill's own text, so class blocks are
# copied verbatim and the parent never pastes prompts by hand.
#
# Usage:
#   build-prompt.sh hunter   <run-dir> <slot> <repo> <scope-dir>
#   build-prompt.sh verifier <run-dir> <candidate.json> <repo> <scope-dir> [second]
#   build-prompt.sh chain    <run-dir> <repo> <scope-dir>
#
# <run-dir> holds threat-model.md (written by reconnaissance) and receives result-<slot>.json,
# verdict-<id>.json, chains.json. Each command prints the prompt path. Tell the agent to read
# that file and follow it exactly.
set -euo pipefail

SK=$(cd "$(dirname "$0")/.." && pwd)
mode=${1:?mode: hunter|verifier|chain}; shift

# section <file> <heading>: a "## heading" section up to the next "## "
section() { awk -v h="## $2" '$0==h{p=1;print;next} /^## /{p=0} p' "$1"; }
# first fenced block after a heading line
fence() { # file heading
  awk -v h="$2" '$0==h{s=1;next} s&&/^```/{c++; if(c==1){next} if(c==2){exit}} s&&c==1{print}' "$1"; }
core() { for h in "$@"; do section "$SK/classes/core.md" "$h"; echo; done; }

case $mode in
hunter)
  run=$1; slot=$2; repo=$3; scope=$4; out=$run/hunter-$slot.md
  {
    echo "# Hunter: $slot"; echo
    echo "## Role"; fence "$SK/HUNTING.md" "#### Role preamble"; echo
    echo "## Inputs"
    echo "Repository to read (read-only): $repo"
    echo "Scope directory: $scope (files.tsv has an origin column committed/uncommitted/both and a category column; diff.patch is the change and is rename-aware; renames.tsv lists moves; uncommitted.patch is the uncommitted part)."
    echo "Threat model from reconnaissance (the human was not asked the open questions, so treat them as UNANSWERED):"
    echo; cat "$run/threat-model.md"; echo
    echo "## Class blocks for your slot ($slot)"; echo
    case $slot in
      access)       section "$SK/classes/core.md" "Core discipline"; echo; core "Access control"
                    echo "### data-isolation (also yours)"; cat "$SK/classes/data-isolation.md"
                    core "Recurring patterns (check these on every diff)" "Validation rules" ;;
      sinks)        section "$SK/classes/core.md" "Core discipline"; echo
                    core "Injection and unsafe sinks" "Resource and file handling" "Recurring patterns (check these on every diff)" "Validation rules" ;;
      logic)        section "$SK/classes/core.md" "Core discipline"; echo
                    core "Business logic and feature abuse" "Chained trust" "Recurring patterns (check these on every diff)" "Validation rules" ;;
      obvious)      section "$SK/classes/core.md" "Core discipline"; echo
                    core "Cryptography and secrets" "Obvious checks" "Recurring patterns (check these on every diff)" "Validation rules"
                    echo "Scope for you: added and modified lines only." ;;
      web-auth)     cat "$SK/classes/web-auth.md" ;;
      client-side)  cat "$SK/classes/client-side.md" ;;
      supply-chain) cat "$SK/classes/supply-chain-ci.md" ;;
      cloud-iac)    cat "$SK/classes/cloud-iac.md" ;;
      ai-llm)       cat "$SK/classes/ai-llm.md" ;;
      electron)     cat "$SK/classes/electron.md" ;;
      mobile)       cat "$SK/classes/mobile.md" ;;
      *) echo "unknown slot $slot" >&2; exit 2 ;;
    esac
    echo; echo "## Hunting method"; fence "$SK/HUNTING.md" "#### Hunting method"
    echo; echo "## Candidate gate"; fence "$SK/HUNTING.md" "#### Candidate gate"
    echo; echo "## Result contract"
    echo "Return exactly one JSON object as your FINAL message and also write the same JSON to $run/result-$slot.json . Do not assign severity. Assigned surfaces: every surface S# in the threat model's HUNTER PLAN for your slot (if the plan lists none for you, assign yourself every changed surface relevant to your classes)."
    awk '/^#### Result contract/{s=1;next} s&&/^```json/{f=1;next} s&&f&&/^```/{exit} s&&f{print}' "$SK/HUNTING.md"
    echo; echo "Fingerprint matches ^[A-Za-z0-9][A-Za-z0-9._:/@+-]*\$ and derives from the root cause. Every assigned surface appears exactly once in surfaces. At most five weaknesses."
  } > "$out"
  echo "$out" ;;

verifier)
  run=$1; cand=$2; repo=$3; scope=$4; second=${5:-}
  id=$(basename "$cand" .json | sed 's/^cand-//'); out=$run/verifier${second:+2}-$id.md
  verdict=$run/verdict${second:+2}-$id.json
  {
    if [ -n "$second" ]; then echo "# Second verifier task: $id"; else echo "# Verifier task: $id"; fi; echo
    extra=""
    [ -n "$second" ] && extra=" and the first verifier record $run/verdict-$id.json"
    echo "Read-only. Read only: this file, the candidate $cand$extra, the threat model $run/threat-model.md, the scope directory $scope (diff.patch, files.tsv, renames.tsv), and the repository $repo (read-only git commands such as git diff -M against the base are fine). Do not read any other candidate or result files, and nothing else on this machine. The human was not asked the open questions in the threat model: treat them as UNANSWERED."
    echo "Write your final JSON verdict to $verdict and also return it as your final message."
    [ -n "$second" ] && echo && echo "You are the SECOND, independent verifier. Independently try to refute the first record and re-derive severity from source BEFORE comparing with the first verifier's severity."
    echo; echo "## Verifier instructions"; fence "$SK/VERIFICATION.md" "## Verifier"
    echo; echo "## Verdict contract (one of these three shapes)"; echo '```json'
    awk '/^#### Verdict contract/{s=1;next} s&&/^```json/{f=1;next} s&&f&&/^```/{exit} s&&f{print}' "$SK/VERIFICATION.md"; echo '```'
    echo; echo "The candidate's claimed_impact is a claim to test, not a conclusion; rate severity yourself."
  } > "$out"
  echo "$out" ;;

chain)
  run=$1; repo=$2; scope=$3; out=$run/chain-prompt.md
  {
    echo "# Chain analysis task"; echo
    echo "Read-only. Read only: the threat model $run/threat-model.md, every $run/result-*.json (hunter results), the repository $repo and the scope dir $scope. Nothing else on this machine. Ignore hunter confidence."
    echo "Write your JSON to $run/chains.json and return it as your final message."; echo
    fence "$SK/HUNTING.md" "## Chain step"
  } > "$out"
  echo "$out" ;;
*) echo "unknown mode $mode" >&2; exit 2 ;;
esac
