# Electron and desktop-webview classes

Original class, built from Electron's own security documentation, published preload and IPC research, and public Electron advisories. Also usable for Tauri, NW.js, CEF and WebView2 shells, with the Electron default facts below re-checked for the framework in use.

## When to use

The diff touches an Electron (or similar desktop-webview) app's trust boundary: `BrowserWindow`/`WebContentsView`/`<webview>` creation or `webPreferences`; preload scripts or `contextBridge.exposeInMainWorld`; `ipcMain.handle/on`, `ipcRenderer`, `webContents.send`, or MessagePorts; `session` permission, display-media, certificate, or `webRequest` handlers; `will-navigate`, `will-redirect`, `setWindowOpenHandler`, or `web-contents-created`; `shell.openExternal/openPath`; `protocol.handle` or `registerSchemesAsPrivileged`; deep-link or `second-instance`/`open-url` handling; `autoUpdater`, electron-builder/forge/fuses/signing/entitlements config; or secret storage in the main process. Server-side issues and generic renderer XSS belong to `web-auth.md` and `client-side.md`; use this class for the escalation path from renderer content to native capability.

## Core discipline

```
- An Electron candidate needs (1) a source the attacker controls: remote or other-user content in a renderer, a deep link, a second-instance argv, a file or drop, an update feed, or a lower-trust window/frame; (2) a capability sink in the main process or preload (shell, fs, child_process, IPC handler, permission grant, capture stream, protocol handler, update install); and (3) the missing boundary between them. Name all three.
- XSS in a renderer is not the finding by itself (client-side.md owns it). It becomes an Electron finding when the change adds or widens what that XSS can reach beyond the page.
- Read the pinned Electron version (package.json, lockfile, builder config) before assigning impact. Documented defaults: nodeIntegration false since 5, contextIsolation true since 12, sandbox true since 20, webSecurity true, allowRunningInsecureContent false, webviewTag false. When a setting is absent from the diff, assume the default for the pinned version; do not report a "missing" flag that already defaults safe.
- Count contextIsolation, sandbox, CSP, navigation and window-open guards, origin checks on IPC senders, and fuses only when visible in the repo and attached to the window or session in question. Controls on one BrowserWindow, session partition, or preload do not protect another.
- Which windows load remote or user-authored content is the key fact. The same controls matter far more on a window that loads a remote workspace than on one that loads only bundled files.
- Packaging, signing, notarization, installer, OS keychain behavior, and shipped fuse state are often outside the diff. Return them as `needs_validation` with the exact check (for example `npx @electron/fuses read --app <path>`), never as confirmed.
```

## Window creation and renderer privilege

- **Node reintroduced to web content**: `nodeIntegration: true`, `nodeIntegrationInSubFrames: true`, `nodeIntegrationInWorker: true`, `contextIsolation: false`, `sandbox: false`, `app.commandLine.appendSwitch('no-sandbox')` or similar on a window that can load remote, user-authored, or redirected content. Any XSS or navigation then yields local code execution. `nodeIntegration: true` also disables the sandbox, and `app.enableSandbox()` overrides per-window `sandbox: false` when called before ready. Confirm which windows actually load untrusted content before rating.
- **Security flags weakened**: `webSecurity: false`, `allowRunningInsecureContent`, `experimentalFeatures`, `enableBlinkFeatures`, `webviewTag: true`, `navigateOnDragDrop`, `--disable-web-security`, `--ignore-certificate-errors`, `--remote-debugging-port`/`--inspect`, `--host-resolver-rules`, `--proxy-server` set in code. Each is a finding only with a reachable remote-content or network-attacker path (`webSecurity: false` disables same-origin policy and also flips the insecure-content default). A flag in a dev-only branch or test harness is a weakness note unless it ships.
- **Window options built from data**: `webPreferences`, `preload`, `partition`, `session`, or the `loadURL` target derived from a URL, config field, or message. Verify the preload path and session cannot be steered, and that the privileged window never loads attacker-chosen URLs.
- **Plain http or file origins**: `loadURL('http://...')` for content with a privileged preload, or privileged pages loaded from `file://`. With a network attacker this is script injection into a privileged context. Prefer a custom scheme with path confinement; `file://` pages can read arbitrary local files, and the `grantFileProtocolExtraPrivileges` fuse (on by default) adds more.
- **`<webview>` and nested contexts**: `allowpopups`, `nodeintegration`, `preload`, `disablewebsecurity`, `src` or `partition` attributes built from data; a missing `will-attach-webview` handler that strips preloads, forces nodeIntegration false, and validates `src`. Electron recommends against `<webview>`, and a guest cannot be made less secure than its embedder through `webpreferences`, but a `preload` attribute runs with Node-capable globals.

## Preload and contextBridge exposure

- **Raw IPC or Electron objects exposed**: `exposeInMainWorld` of `ipcRenderer`, `ipcRenderer.send/invoke/on` with a caller-chosen channel, `shell`, `require`, `fs`, `child_process`, `process`, `Buffer`, or a library object (logger, emitter) holding file or process capability. Any script in the page can then send arbitrary channels or reach the sink. Verify exposed functions use a fixed channel and validate arguments.
- **Listener wrappers that leak the event**: `on: ipcRenderer.on`, or a callback passed straight to `ipcRenderer.on`, hands the page `event.sender`. The wrapper must forward only the data value.
- **Preload restoring Node globals** (`window.process = process`, `window.Buffer = Buffer`, `global.require`) or assigning privileged helpers on `window` with `contextIsolation: false`: page script can overwrite them via prototype pollution or reassignment, changing results or bypassing checks.
- **Thin wrapper over a dangerous main handler**: `openExternal(url)`, `readFile(path)`, `runCommand(cmd)`, `download(url)`, `setClipboard`, `getToken()` exposed with no validation in preload or main. Trace the exposed function to the main-process handler; validation must exist in main, not only in the preload or UI.
- **`nodeIntegrationInSubFrames` with a preload**: the preload runs in every iframe, so the bridge may reach frames that load other origins. Check `process.isMainFrame` and origin gating before exposing anything sensitive.

## IPC handlers and sender trust

- **Missing sender validation**: `ipcMain.handle/on` that performs a privileged action or returns confidential data without checking `event.senderFrame.origin` (the origin, not a URL substring or `webContents.getURL()`) and, where relevant, the specific WebContents id, against an allowlist. A subframe, popup, navigated window, or remote content that obtains `ipcRenderer` reaches it. Rate by what the handler can do.
- **Origin check by weak match**: `startsWith`, `includes`, `endsWith`, unanchored regex, or comparing `senderFrame.url` to a base. Look-alike hosts, userinfo, and paths bypass these. Require parsed-origin equality.
- **Capability confusion across windows and tenants**: a handler registered globally while only one window should use it; one workspace or server's content invoking handlers that act on another workspace's session, credentials, or files because the handler takes a server or workspace identifier from the renderer.
- **Argument trust**: renderer-supplied paths, URLs, command names, window ids, or setting keys reaching `fs`, `shell`, `child_process`, `app.relaunch`, `dialog` defaults, `webContents.executeJavaScript`, `loadURL`, or settings writers without validation, confinement (resolve, then check the prefix), or allowlisting. Preference writers that accept arbitrary keys can switch off security flags or redirect update, feed, or server URLs on next start.
- **Privileged results returned to the page**: handlers returning tokens, credentials, full config, file contents, or process env.
- **Main-to-renderer pushes**: `webContents.send` or `executeJavaScript` with string interpolation of untrusted data, or `send` to every window including ones showing foreign content.

## Navigation, windows, and external launch

- **`will-navigate` only**: `will-navigate` does not fire for programmatic `loadURL`, in-page navigation, or redirects; `will-redirect` and `will-frame-navigate` exist. A same-origin or allowlisted URL that redirects (upload or download endpoints that 302 to storage, open redirects) escapes a `will-navigate` check. Look for handlers on only one of these events and for prefix or substring host tests instead of parsed `new URL(...).origin` equality.
- **Missing or permissive `setWindowOpenHandler`**: absent, returning `{action: 'allow'}`, or allowing by a weak URL test. Child windows receive their own `webPreferences` through `overrideBrowserWindowOptions`; confirm overrides cannot loosen sandbox or isolation. Also check the `web-contents-created` hook is registered so guards cover windows, views, and webviews created later.
- **`shell.openExternal` / `openPath` with unvalidated input**: URLs or paths from messages, links, deep links, or IPC. Dangerous schemes (`file:`, custom app handlers, `smb:`, `javascript:`, `data:` and others) can launch local programs or leak NTLM hashes. Require a parsed-scheme allowlist (`https:`, `mailto:` and similar) at the main-process sink, not just in the renderer. `openPath`/`showItemInFolder`/`trashItem` need path confinement.
- **In-app handling of foreign links**: links to user-uploaded files or same-host paths opening inside a privileged window instead of the external browser, so attacker-authored HTML runs with the app's bridge.
- **Drag-and-drop and file handlers**: dropped file paths or `file://` URLs passed to loaders, or `webUtils.getPathForFile` results sent to main handlers that read or upload them.

## Permissions, capture, and device surfaces

- **Permission handlers that grant by default**: Electron approves every permission request unless a handler is set. Flag a `setPermissionRequestHandler`/`setPermissionCheckHandler` that returns true for all, ignores `webContents`/`requestingOrigin`/`isMainFrame`, or compares the URL by substring; also a missing check handler beside a request handler. Check which session each handler is attached to (default session or a partition).
- **Display-media and screen capture**: a `setDisplayMediaRequestHandler` that calls `callback({video: sources[0], audio: 'loopback'})` without user selection, without vetting `request.frame` origin, or with a `WebFrameMain` source (which captures the whole tab). Any connected or embedded workspace or iframe could then request a live screen or system-audio stream. The same applies to `desktopCapturer` results returned to the renderer through IPC, and to camera and microphone (`media`), clipboard, notifications, geolocation, and HID/serial/USB `setDevicePermissionHandler` grants.
- **Device selection auto-grants**: `select-bluetooth-device`, `select-hid-device`, `select-usb-device` handlers that pick the first device or persist grants without a user choice.
- **Trusted-origin confusion**: the main process granting a capability because `getURL()`, `senderFrame.url`, a hostname substring, a configured "trusted server" list that the user or remote server can extend, or an iframe's parent says so. Verify the origin comes from the actual requesting frame and that allowlist entries cannot be added by an attacker (workspace URLs, custom server fields).
- **Certificate and auth handlers**: `certificate-error` calling `callback(true)`, `setCertificateVerifyProc` returning 0 broadly, `login` handlers supplying credentials without checking `authInfo.host`/realm; proxy or `NODE_EXTRA_CA_CERTS` fallbacks. These expose all traffic to a network attacker; scope matters (one pinned host or any host).

## Protocols, schemes, and local servers

- **`registerSchemesAsPrivileged` over-privilege**: `bypassCSP`, `secure`, `standard`, `supportFetchAPI`, `corsEnabled`, `stream` set on a scheme that serves attacker-influenceable content, or a custom scheme whose files are readable cross-origin. A privilege or handler that lets other origins read these responses breaks isolation.
- **`protocol.handle` path confinement and caller trust**: request paths joined to a base directory without a resolve-and-prefix check (`..`, encoded slashes, backslashes on Windows); handlers deciding access from `referrer` instead of `request.initiatorOrigin`; a handler registered on the wrong session or partition.
- **Embedded local servers and IPC sockets**: HTTP, WebSocket, or named-pipe servers bound to `0.0.0.0` or a predictable localhost port without Origin/Host checks or a per-launch token. Any web page or local user can drive the app (DNS rebinding, cross-site WebSocket).
- **Deep links**: `setAsDefaultProtocolClient`, `open-url`, `second-instance` argv, or `process.argv` URLs acted on without parsing and allowlisting host, path, and params; link data flowing to navigation, auth or token exchange, file access, or shell calls. On Windows, protocol registration without a `--` terminator before the URL allows command-line switch injection from a web page.

## Update, packaging, and supply chain

- **Update feed and install trust**: `autoUpdater.setFeedURL`, electron-updater, or builder `publish` over `http:`; a feed or server URL read from user-editable config or a renderer-settable value; update checks that skip signature or checksum validation; `allowAnyVersion` or downgrade; custom updater code that downloads and executes. macOS Squirrel requires signing; verify the diff does not replace it with a custom download-and-run path.
- **Fuses and integrity**: forge or builder fuse config enabling `runAsNode`, `nodeOptions`, `nodeCliInspect`, leaving `onlyLoadAppFromAsar` and `embeddedAsarIntegrityValidation` off, or removing existing hardening; `asar: false`; unpacked native code or scripts writable by the user. Treat shipped state as `needs_validation`; flag only config the diff weakens. Fuse changes are applied after packaging, so confirm they run before signing.
- **Signing and entitlements**: new or broadened macOS entitlements (`allow-unsigned-executable-memory`, `disable-library-validation`, `allow-dyld-environment-variables`), `hardenedRuntime` off, notarization or signing skipped in release config, camera, mic, or screen usage strings added.
- **Electron version and dependency pinning**: a downgrade, a loosened range (`^`, `latest`), or an Electron major that predates a relevant fix. Unsupported majors receive no backports. Claim a specific advisory only if the pinned version is confirmed in range from the advisory text; otherwise `needs_validation`.
- **Native and preload dependencies, postinstall**: new native modules, `postinstall` or build scripts, or remote-fetched binaries in the packaging pipeline.

## Secrets, storage, and logging

- **Tokens and credentials at rest**: auth tokens, session cookies, or API keys in plaintext JSON or config, `electron-store`, `localStorage` of a privileged origin, or logs. `safeStorage` on Linux can fall back to a `basic_text` backend with a hardcoded password (check `getSelectedStorageBackend()`); encryption with a key stored beside the data is not protection. Rate by reader: other local users or other apps under the same OS user are weaker readers than a renderer-reachable IPC read.
- **Secrets crossing windows**: tokens for one workspace or server returned to renderer content of another, or attached to requests whose destination is built from renderer data.
- **Logging**: main-process or preload logs (including crash reports and `console` forwarded to files) containing tokens, deep-link URLs with auth codes, message content, or full IPC payloads, written to world-readable or uploaded locations.
- **Cookie and session partitions**: sharing one persistent partition between trusted and foreign-origin content, or removing the `cookieEncryption` fuse on a build that stores session cookies.

## Validation rules

```
1. Name the renderer-controllable or remote source, the window/frame/session that hosts it, the capability sink, and the missing boundary. Trace the path across preload, IPC channel, and main handler; each hop must be visible in source.
2. Check the pinned Electron version and the documented default for each setting before reporting; a flag absent from the diff is not a finding when the pinned default is safe.
3. Count a control only if visible and attached to the same window, session, or handler: contextIsolation, sandbox, CSP, navigation/window-open/will-redirect guards, sender-origin checks, permission handlers, and fuses.
4. For IPC and bridge candidates, show exactly what the page can call (channel, arguments) and what the handler does with them. A narrow, argument-validated, fixed-channel wrapper is not a finding.
5. For permission, capture, and trusted-origin candidates, show which origin or frame can trigger the grant and what stream, data, or action results. A grant to the app's own bundled origin only is not a finding.
6. For update, packaging, fuse, signing, and OS-keychain facts not shown in the repo, return `needs_validation` with the exact check (for example `npx @electron/fuses read --app <path>`, rendered builder config, installed Info.plist or entitlements).
7. A misconfiguration with no reachable attacker input (the window loads only bundled content, dev-only code, a test harness) is a weakness note, not a finding.
8. Do not run, install, or build the target; read configuration and code only. Show the change introduced or exposed it.
```
