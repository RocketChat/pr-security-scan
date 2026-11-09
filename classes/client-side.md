# Client-side and browser classes

Adapted from Cloudflare's `CLIENT-SIDE.md` (MIT), reframed for diff-scoped review, with one added class (authenticated request construction).

## When to use

The diff touches code that runs in a browser, webview, or extension and makes a trust decision or renders attacker-influenceable content: SPA components, message/markdown/UI-block rendering, URL or request construction on the client, `postMessage` handlers, service workers, browser storage, or client-side navigation. These paths include sources the server never sees: URL fragments, `window.name`, cross-window messages, and previously cached content. Server-side CSRF, sessions, and auth callbacks belong to `web-auth.md`.

## Core discipline

```
- A client-side candidate needs a controllable source and an executing or disclosing sink. Name both and show attacker-influenced data reaching the sink.
- The impact must reach a victim's session, another origin, or shared persistence. Self-injection and disclosure of the attacker's own data are not findings.
- Framework escaping, same-origin policy, CSP, COOP/CORP, service-worker scope, and modern noopener defaults are real controls. Verify them before assigning impact.
- Data that other users author (messages, blocks, attachments, display names, app-provided content) is untrusted input to the victim's browser. Treat every field of it as attacker-controlled, including ids and URLs the UI "just passes along".
- Use `confirmed` for complete source evidence of the client path. Use `needs_validation` when renderer, deployed header, extension permission, or browser-policy behavior is required but not in the repository.
```

## Authenticated request construction (confused deputy)

The client attaches the user's credentials to a request whose destination or path is built from data an attacker controls.
- **Unencoded path or query interpolation**: an id, filename, or URL fragment taken from a message, block, attachment, or other user's record is interpolated into a REST path (`/items/${id}`) or query string without `encodeURIComponent`. `..` segments are normalized by `fetch`, so the credentialed request lands on a different endpoint chosen by the attacker and performed with the victim's authority. Check which state-changing endpoints lack a strict body schema and step-up authentication (such as 2FA), since they are the reachable ones.
- **Credentials appended by a weak origin test**: session tokens, user-id headers, or other auth values added to a URL because it starts with `http`, starts with the server URL (prefix match), or contains the host, instead of comparing the parsed origin. Look for look-alike hosts (`server.com.evil.net`), userinfo (`server.com@evil.net`), and call sites that skip the check.
- **Open redirect or SSRF-like fetch from client data**: a client-side fetch, image load, or `window.location` assignment to a URL taken from message content, with credentials or cookies in scope.
Require the lower-trust author, the field they control, the unencoded or weakly checked construction, and the concrete endpoint or origin the victim's request reaches.

## DOM and object state

- **DOM-based XSS**: `location`, `document.referrer`, `window.name`, message data, storage, or other users' content reaching `innerHTML`, `dangerouslySetInnerHTML`, `document.write`, string-evaluating APIs, `javascript:`/`data:` URLs, jQuery HTML APIs, or markdown/HTML renderers with sanitization disabled or an allowlist widened. Interpolation escaped by the framework is not a finding.
- **DOM clobbering**: attacker `id`/`name` attributes that survive sanitization and shadow a global or config object later trusted by code.
- **Prototype pollution and gadget**: an attacker-controlled key reaching a recursive merge or path assignment, plus a reachable gadget. Pollution without a gadget is not enough.

## Cross-origin messaging and network

- **`postMessage` origin and source trust**: a handler acting on `event.data` without an exact origin allowlist (and `event.source` where frames share an origin); sensitive data sent to `*`. Substring, prefix, suffix, or unanchored-regex origin checks are not origin checks.
- **Cross-site WebSocket use**: an upgrade accepting ambient cookies without an `Origin` check or channel token, with a security-relevant handler behind it.
- **Credentialed CORS trust**: a reflected or weakly matched `Origin` with credentials and a sensitive response.

## Storage, workers, navigation

- **Browser storage disclosure and stale authorization**: tokens, private responses, or authorization decisions in `localStorage`, `sessionStorage`, IndexedDB, Cache Storage, or extension storage readable by a less-authorized reader or kept after logout/revocation. Storing a token alone is not a finding.
- **Service-worker scope and cache confusion**: attacker-influenceable content becoming the worker script or scope; personalized responses cached without account, tenant, or authorization state.
- **Client-side navigation confusion**: a client source controlling navigation without scheme and destination policy (`javascript:`, `data:`); reverse tabnabbing only where `window.opener` is explicitly retained.
- **Clickjacking**: a framed, state-changing action without effective `frame-ancestors`/`X-Frame-Options`. Read-only content without headers is a hardening note.

## Validation rules

```
1. Cite the source, sink, browser policy, affected origin or session, and the observable mutation or disclosure.
2. For request-construction claims, show the unencoded or weakly validated value, the exact URL the browser requests after normalization, and an endpoint where the victim's authority has consequences. A fixed or mismatched request body does not limit the impact: the harmful targets are state-changing routes that ignore the body or accept extra keys (for example routes with no body validator and no step-up authentication). Enumerate them from the route definitions (state-changing handlers with no request-body schema and no step-up authentication requirement) before concluding that no target exists.
3. For XSS, show the data survives the framework and any sanitizer on the path. For prototype pollution, prove a gadget. For clobbering, prove the markup survives and the shadowed value is used.
4. For messaging, CORS, and WebSocket claims, show the exact origin or source validation and the protected state or action exposed; confirm CSP, cookies, and SameSite do not already block it.
5. A click requirement is not a reason to reject when the attacker controls the rendered control and it is indistinguishable from legitimate UI.
6. Show the change introduced or exposed it.
```
