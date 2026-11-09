# Core attack classes

Adapted from Cloudflare's `ATTACK-CLASSES.md` (MIT). Hunters receive the Core discipline, the class sections their slot selects, and the Validation rules, copied verbatim.

## Core discipline

```
- Scope is this change. Hunt in added and modified code and in existing code the change newly reaches, trusts, or unprotects. Read elsewhere only to establish controls and reachability.
- A candidate needs a lower-trust attacker, an accepted input or action, a crossed boundary, an affected resource, and a concrete result. Missing best practices, self-impact, and same-principal authority are not findings.
- Follow input to the sink. Do not stop at the obvious direct path: look for data stored safely and used dangerously elsewhere, injection through field names, keys, headers and metadata, and parallel paths to the same effect.
- Compare sibling controls for equivalence, not just presence. The effective policy is the weakest parallel path.
- A flag is not a finding. Trace the impact before reporting it.
```

## Access control

Verify the caller cannot do something outside its authority, with the right permission for the right resource through the right mechanism.
- Is there a path to the same state change that checks a weaker permission?
- Can a request-body field override what the permission system intended to restrict (mass assignment, role/owner/tenant fields)?
- Does the endpoint gate on authentication but forget authorization? Is a new route missing a control its siblings have?
- Do bulk, batch, export, import, and background paths enforce per-item permissions?
- Does an ID in the path or body select a resource without an ownership check (IDOR)?

## Injection and unsafe sinks

Trace untrusted input from entry to a dangerous sink: SQL/NoSQL queries, shell commands, template engines, HTML output, file paths, redirects, deserialization, regex, log and header construction, secondary systems (logs, caches, search indexes).
- Indirect injection: data stored safely and later used in a dangerous context by different code.
- Injection through field names, keys, headers, and metadata, not just values.
- Dynamic evaluation (`eval`, `exec`, `Function`, dynamic `import`, `child_process`, `vm`) fed from lower-trust data.

## Resource and file handling

- Path traversal, including symlinks, encoded sequences, and null bytes.
- SSRF: attacker-controlled URLs fetched by the server, including redirects, DNS rebinding, and URL parser differentials; webhooks and callbacks.
- Unsafe deserialization, archive extraction (zip slip), temp-file handling.
- TOCTOU between check and use on file operations.
- Memory safety only when the diff touches native or `unsafe` code: buffer overflow, use-after-free, integer overflow.

## Cryptography and secrets

- Weak randomness for tokens, keys, nonces; broken key derivation; missing MAC verification; nonce reuse; ECB or unauthenticated encryption; static IVs.
- Hardcoded secrets, and secrets in logs, error messages, URLs, or client-visible responses.
- Timing side channels on secret comparison.
- What happens when a crypto operation fails: does the error path fall back to no crypto?

## Business logic and feature abuse

Standard scanners miss these. For each changed workflow:
- State-machine violations: skip steps, go backward, replay a completed flow, partial failure with no rollback.
- Races with business impact: check-then-act without atomicity (double-spend, double-approve, lost update).
- Numeric manipulation: negative, zero, overflow, precision loss, string/number coercion.
- Implicit trust: data from storage, config, plugins, or another component assumed safe because it was "validated on the way in", when another path wrote it.
- Time-based logic, default and fallback behavior when config is missing, a flag is off, or a dependency is down.
- Features as attack paths: export or backup including data above the requester's access; import that bypasses validation or overwrites; search/filter/sort as an oracle for hidden data; enumeration through differing errors; preview/draft/staging leakage; user-set webhook or callback URLs.

## Chained trust

Individually allowed or contained behavior becomes a vulnerability when another component relies on a stronger guarantee.
- Cross-component gaps: component A validates and passes to B; compare what A guarantees with what B assumes (truncation, coercion, normalization, tenant scope).
- Second-order use: a stored field becomes a path, URL, regex, template, or policy expression later.
- Scope and capability growth through delegation, refresh, caching, or role change.
- Ordering and rollback: stale state accepted after revoke, undelete, restore, cancellation, or migration.
Establish each prerequisite; do not assume a downstream effect. Combine across candidates in the chain step, not here.

## Obvious checks

Cheap and literal; run on added and modified lines only. Report each result, then trace impact for anything that hits.
- Hardcoded passwords, API keys, tokens, private keys (`password`, `secret`, `apikey`, `token`, `Bearer`, `-----BEGIN`), and committed `.env`, `*.pem`, `*.key`, `credentials.json`.
- Security-related `TODO`/`FIXME`/`HACK` added by the change (`add auth`, `validate input`, `skip permission check`) and commented-out checks.
- Debug or dev mode that can be enabled in production by env var, query parameter, or header; test/seed credentials; unprotected `/debug`, `/admin`, `/metrics`, `/env`, `/config` handlers.
- `eval`/`exec`/dynamic import on non-constant input. Open redirects (`redirect`, `return`, `next`, `url`, `goto` parameters feeding a redirect). CORS `*` with credentials. Stack traces or SQL errors returned to clients.
- Cookie flags and TLS only when the cookie carries a session or secret and script access or plaintext transport is realistic.
Do not report a flag without its impact. A cookie without `HttpOnly` that carries nothing sensitive, or an error that names a field that is never populated with sensitive data, is not a finding.

## Recurring patterns (check these on every diff)

Vulnerabilities in web applications and APIs keep taking a few shapes. When a changed line touches one, trace it fully; each has a precise exploit condition.
- **Operator injection through an untyped value**: a request value reaches a document-database or query-builder filter (`find`, `findOne`, `update`, `delete`, model helpers) without a string check. A JSON schema that lists `minLength`/`maxLength`/`pattern` but no `type: 'string'` does not stop an operator object such as `{"$ne": null}`, because those keywords only apply to strings. A truthiness check (`!value`) is not a type check. Look for the guard, and for whether the data layer has its own guard (a second layer makes a missing first layer hardening, not a finding).
- **Trusting an unsigned field next to a signed one**: an identity-provider token is verified, then a client-supplied `email`, `username`, or id is merged into the result. Account linking by email is the usual sink.
- **Ownership or parent binding dropped**: a lookup by id that used to compare the record's parent or owner (for example `file.parentId`, `comment.ownerId`) to the checked resource. Removing a "redundant" equality check is the typical change.
- **Parameter and object confusion**: the authorization check uses one field and the query another (`resourceId` vs `parentId`), or the check runs on a caller-supplied object instead of the one loaded from the database.
- **Schema allowance**: a request or message schema that permits unknown properties (no `additionalProperties: false`, or a "may include extra keys" helper) lets users set fields the server later trusts (`pinned`, `approved`, `isAdmin`, precomputed render or URL fields).
- **Result of a check discarded**: `await hasPermission(...)` or `await canAccess(...)` whose boolean is not tested.
- **Cache keys that omit an input**: a permission, tenant, or resource result cached by user and permission only.
- **Weak origin and prefix tests** (server or client): `startsWith`, `includes`, or a regex on a URL or origin string instead of comparing the parsed origin. `startsWith('')` is always true, so an empty setting disables the check.
- **Credentials in transit to attacker-influenced destinations**: tokens appended to URLs, forwarded in headers, or sent by a client to a path or host built from user-supplied data.
- **Security defaults flipped**: a setting default, feature flag, or fail-open fallback changed inside an unrelated diff.

## Validation rules

```
1. Name the lower-trust attacker, their input, the intended control, the crossed boundary, the affected resource, and the concrete result.
2. Cite the strongest visible control on the path and say why it does not stop the attack. If another layer stops it, there is no candidate.
3. Confirm the change introduced or exposed the issue.
4. Do not strengthen a crash into code execution, ordinary work into shared availability, or a same-principal action into privilege gain.
5. If a decisive fact is outside the repository (deployment, proxy, flag, secret value), return it as an unknown with the exact question. Do not guess either way.
6. Return nothing when nothing survives these gates.
```
