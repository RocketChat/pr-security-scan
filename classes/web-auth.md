# HTTP and authentication classes

Adapted from Cloudflare's `WEB-PROTOCOL-AND-AUTH.md` (MIT).

## When to use

The diff touches sessions, cookies, JWT, OAuth/OIDC, SAML, MFA, passkeys, account linking or recovery, API keys, mTLS, CORS/CSRF, caching, reverse-proxy or header handling, or custom HTTP parsing. Access-control review asks whether a principal may do an operation; this file asks whether the HTTP or identity layer can confuse which principal, request, assurance level, or token the operation belongs to.

## Core discipline

```
- Framing and cache findings need two interpretations of the same request, response, or key. Name both components and the exact normalized value on each side.
- For every credential, find the signature or secret verification and every binding its role requires: issuer, audience, origin, relying party, client, session, principal, resource, assurance, expiry, one-time state.
- Host, Forwarded, X-Forwarded-*, Origin, Referer, redirect targets, callback state and request-derived URLs are trust decisions. Trace each to the affected identity or response.
- A missing header, cookie attribute, MFA prompt, or rate limit is not a finding alone. Require an accepted invalid request, cross-principal impact, assurance downgrade, or credential disclosure.
- Proxy chains, edge cache keys, IdP policy, certificate trust, and deployed auth modes are often outside the repository. Record an exact unknown rather than asserting their behavior.
```

## Request framing, cache, and host trust
- **Framing/desync**: front end and back end disagree on length or header normalization (multiple `Content-Length`, `Transfer-Encoding`, downgrade). Only relevant when the repo contains a proxy or custom parser.
- **Cache poisoning**: a request value changes cached content but is absent from the cache key.
- **Cache deception / private-response caching**: a private dynamic path cached as static, or a response cached without its identity inputs.
- **Host and forwarded-header trust**: untrusted host/proxy metadata drives absolute URLs, tenant routing, reset links, cache keys, or the client address used for authorization. Who can supply it, and does trusted ingress strip it?
- **Response-header injection**: untrusted data reaches `Location`, `Set-Cookie`, or CSP with unsafe control characters. Verify framework rejection first.

## Browser sessions
- **CSRF**: cookie-authenticated state-changing endpoint accepting a cross-site request with no effective token, same-site binding, or Origin/Referer check. Bearer-token routes and read-only routes do not qualify. SameSite counts only for the cookie and browser contexts actually in use.
- **Session fixation/invalidation**: no rotation on login, MFA, privilege change; still valid after logout, password change, revoke.
- **Cookie scope/transport**: over-broad `Domain`/`Path` or insecure transport on a sensitive cookie. A missing flag alone is a weakness note.

## Federated identity
First establish the component's role: authorization-server controls (redirect allowlisting, code issuance) do not belong to a relying party.
- **JWT**: signature verification, server-pinned algorithm and key source, then `exp`, `nbf`, `aud`, `iss`; `kid`/`jku`/`x5u` as untrusted key selectors; decode-without-verify paths. A valid token for another service is invalid here.
- **OAuth/OIDC**: exact `redirect_uri` ownership (authorization server), session-bound `state`, PKCE and code binding, ID-token issuer/audience/nonce, selected-IdP binding.
- **SAML**: the element whose signature is validated must be the element used as identity; safe XML parsing; validity window, audience, recipient, replay state.

## MFA, passkeys, account transitions
- **MFA enrollment and downgrade**: enrollment, replacement, disablement, recovery-code generation, and trusted-device creation require the intended prior assurance; a valid first factor must not replace the second.
- **Step-up binding**: a challenge must bind to principal, session, assurance target, and operation; compare UI, API, batch and resumed paths.
- **WebAuthn**: challenge, RP ID, origin, credential membership, signature, user verification where policy needs it.
- **Account linking**: adding an IdP, email, phone, or device needs a current session, verified ownership, step-up where policy needs it, and callback state bound to the initiating account.
- **Recovery**: reset tokens, support recovery, backup codes, email/phone change. Verify randomness, user/action binding, expiry, one-time state, delivery URL trust, and invalidation of prior tokens and sessions.

## API keys and mTLS
- **API-key scope**: a key authenticating beyond its server-side record, or request parameters overriding its bindings; publishable vs secret key confusion; revocation caches.
- **API-key exposure**: keys in client bundles, URLs, logs, errors, build artifacts. A public identifier called a key is not a secret.
- **mTLS identity**: identity headers trusted from any peer; subject text mapped to an account incorrectly; wrong trust domain or usage. Behind a terminating proxy, verify only the proxy can connect and it strips incoming identity headers.
- **Certificate fallback**: expired, revoked, or renewal-failed certificates silently falling back to bearer-only or anonymous operation.

## Validation rules

```
1. Apply the source-visibility gate: if proxy chain, edge cache, IdP policy, certificate trust, browser cookie behavior or deployed auth mode is required and not in the repository, return an exact unknown.
2. For framing and cache findings, name both components and the divergent parse or key.
3. For token, MFA, passkey, linking, recovery, API-key and mTLS findings, cite the verification line and the missing principal/session/resource/origin/audience/action/assurance binding, and show the server accepts the invalid transition or credential.
4. For CSRF, name the ambient credential, the state-changing route, the accepted cross-site request shape, the cookie policy, and the missing effective check.
5. Verify framework and library defaults at the pinned version. If the version or configuration is unknown, return an unknown; do not downgrade a critical claim into a confirmed lower one.
6. Show the change introduced or exposed it.
```
