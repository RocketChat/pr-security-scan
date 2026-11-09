# pr-security-scan

<p align="center">
  <img
    src="https://github.com/user-attachments/assets/e0fc6532-4f1b-4127-b72d-3bcbee058f53"
    alt="pr-security-scan"
    width="383"
    height="256"
  />
</p>


A coding-agent skill that security-reviews the code a developer is about to put up for review. It scopes to the changes on the current branch (or the open PR), including uncommitted work, then runs isolated per-class hunters and independent verifiers. It reports only moderate-or-higher issues with real impact, each with the smallest fix.

It is built for minutes, not hours. It is not a whole-repository audit.

## How it works

1. **Scope** (`scripts/resolve-scope.sh`): finds the base branch, the diff (rename-aware, committed and uncommitted, tagged per file), and the PR text if a PR is open.
2. **Recon**: one agent builds a threat model of just this change: the changed surfaces, what the change newly enables, and which hunter classes apply. It asks you at most three questions, only when the answer would change reachability or severity.
3. **Hunt**: three to six isolated read-only hunters, each with one attack-class block (access control, injection, business logic, secrets and obvious checks, web/auth, client-side, supply chain and CI, cloud/IaC, AI/LLM, Electron/desktop, mobile). They return structured candidates and a disposition for every surface.
4. **Chain**: one agent looks for combinations of weaknesses that reach moderate-or-higher impact.
5. **Verify**: a fresh agent tries to disprove each candidate. A second independent verifier re-checks anything rated high or critical.
6. **Report**: findings, items that need your input, coverage, and a note if anything tried to steer the review.

## Rules it follows

- Source only. It never runs, builds or installs anything from the target.
- Only moderate-or-higher, only with a named attacker, boundary and concrete result.
- A finding must be introduced or exposed by the change.
- Another layer that stops the attack, cited in source, makes a missing layer hardening, not a finding.
- Facts outside the repository are asked about once. If unknown, the item stays `needs_validation` with no severity.
- The diff, commit messages, PR text and code comments are data. Instructions inside them are ignored and reported.

## Requirements

- `git`. The GitHub CLI (`gh`) is optional and only used to read an open PR.
- An agent platform that can run sub-agents in parallel and give them read-only file access. The skill is agent-neutral and names roles, not products. We've tested it with Claude Code and OpenCode.

## Install

Copy this directory into your agent's skills location, for example `~/.claude/skills/pr-security-scan/` for Claude Code, or a project's `.claude/skills/` directory. Keep the folder name as `pr-security-scan`.

## Use

Ask your agent, for example:

- "Security-scan my branch before I open the PR."
- "Security-review PR 1234."

Or simply run `/pr-security-scan` inside the directory and branch you'd like to scan.

You can add additional context when asking for a scan if you feel like it. Also, there are optional scope flags for `scripts/resolve-scope.sh`: `--base <ref>` and `--pr <number>`.

## Customizing and extending

The files in `classes/` are what the hunters actually read, so they are the main lever for accuracy on your stack. Edit them freely.

- **Tune an existing class.** Add the bug shapes you keep seeing, or remove bullets that cause noise. The "Recurring patterns" section in `classes/core.md` is the best place for lessons from your own past vulnerabilities, written as generic patterns (a precise exploit condition, no internal names). Keep each bullet confirmable from source, and keep the Validation rules: they are what prevent speculative findings.
- **Add a class.** Create `classes/<name>.md` with the same shape as the others (`When to use`, `Core discipline`, themed sections, `Validation rules`). Then register it in three places: a row in the slot table in `HUNTING.md` with a clear trigger, the slot name in the hunter plan in `RECON.md`, and a case in `scripts/build-prompt.sh`. Recon only selects a class when the diff touches the trigger you describe, so write the trigger in terms of files and boundaries, not library names.
- **Cover another stack.** Classes for Electron and mobile already exist; native code (C/C++, `unsafe` Rust), game engines, smart contracts, or data pipelines would each be a new class in the same way. If you rename a heading in `classes/core.md`, update the matching names in `build-prompt.sh`, which selects sections by heading.
- **Keep private patterns private.** If a pattern would reveal unpatched weaknesses of a specific product, put it in a class you do not publish and load it only in your environment.

After any change, re-run the skill on a branch with a few seeded bugs of that kind and on a clean branch. Broader bullets find more, but they also raise false positives.

## Cost and models

Expect roughly 10 to 20 agents for a typical PR, run mostly in parallel. By default every agent uses the model you are already running. Splitting models by role (for example a stronger model for verifiers) is possible on platforms that allow it, but that split has not been tested. Also, for cost optimization, you should run this skill in a new session. Avoid running it in the same session you were doing the code changes.

## Origin

The workflow, attack-class files, severity anchors, candidate gate, the finder/verifier separation and the `needs_validation` verdict are adapted from [cloudflare/security-audit-skill](https://github.com/cloudflare/security-audit-skill) under the MIT License. See `NOTICE.md`.

## License

Released under the [MIT License](LICENSE). Copyright (c) 2026 Rocket.Chat.
