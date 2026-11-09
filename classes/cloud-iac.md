# Cloud and infrastructure-as-code classes

Adapted from Cloudflare's `CLOUD-AND-DEPLOYMENT.md` (MIT).

## When to use

The diff touches IAM or cloud policy, Terraform or similar IaC, Kubernetes manifests or Helm charts, Dockerfiles and compose files, serverless or edge configuration, ingress, object storage policy, or environment-specific configuration. Source often states intent rather than live fact, so separate source-confirmed defects from deployment unknowns.

## Core discipline

```
- Do not infer a live exposure from a manifest alone. Establish which environment consumes it, which defaults or overlays modify it, and whether the source path is active.
- Map each workload identity to the operations and resources it can reach. Broad policy is a finding only when lower-trust input can reach an unauthorized action.
- Ingress, proxies, mesh and admission policy are real boundaries, but count a control only when its configuration and attachment are visible.
- A secret reference is not secret disclosure. Require a lower-trust reader, output, artifact, log path, or unsafe fallback.
- Account policy, network attachment, runtime admission, hosted metadata, and drift are usually not in the repository. Return them as exact unknowns.
```

## Workload identity and IAM
- **Identity overreach**: a workload or function identity can act on tenants, accounts, or resources beyond its role, and untrusted request or job input selects the target (wildcard resources, missing conditions).
- **Cross-account/tenant role confusion**: role assumption, external IDs, token exchange, or federation accepting claims not bound to the intended account, audience, repository, namespace, or workload.
- **Application authorization delegated to cloud metadata**: the app trusts caller-supplied identity headers, tags, labels, or account IDs not verified against the control plane.

## Ingress, network, control plane
- **Unexpected reachability**: an ingress, service, listener, security group, port mapping, or bind address exposing an admin, debug, metrics, or internal API to a lower-trust network. A repository-controlled public route to a sensitive handler can be confirmed; absence of network control alone is an unknown.
- **Trusted-proxy and mesh bypass**: a backend accepting forwarded identity from peers outside the intended ingress, or an alternate port or health path bypassing the mesh.
- **Metadata and internal reachability**: untrusted URL or destination reaching instance metadata, control-plane sockets, or internal APIs with workload credentials.

## Containers and orchestration
- **Host or control-plane capability exposure**: privileged mode, added capabilities, host namespaces or paths, runtime sockets, service-account tokens reachable by lower-trust workloads. A missing seccomp profile or read-only root alone is a weakness note.
- **Admission and policy inconsistency**: one deploy path enforces image, privilege, or namespace policy while another (job, upgrade, restore) does not.
- **Label and namespace trust**: policy matching on labels or names that a less-trusted principal can set.

## Configuration and secrets
- **Control precedence drift**: dev values, chart defaults, env vars, flags, or per-region overlays disabling authentication, transport security, tenant scoping, or audit in a deployed environment. Render the final value for each maintained environment, not just the base file.
- **Secret exposure across workload boundaries**: secrets in logs, args, shared env, broad volumes, build outputs, or read APIs reachable by another workload.
- **Credential renewal and fallback**: a failed refresh or rotation leaving a stale credential active or falling back to a less trusted identity mode.

## Storage, events, edge
- **Object and signed-URL policy**: bucket or URL policy not binding principal, operation, namespace, audience, or expiry; list and version operations and writes, not just reads.
- **Event-source identity**: functions trusting event body fields as the source without verifying the provider-signed envelope, topic, account, and replay state.
- **Edge/origin mismatch**: an edge runtime assuming a secret or policy that differs from the origin, with fallback changing authority or cache behavior.

## Validation rules

```
1. Establish the active source path and effective deployment object; otherwise return an unknown naming the missing rendered manifest or owner-observed attachment.
2. Name the lower-trust caller or workload, the cloud or application identity, the controllable selector, the affected resource, and the unauthorized operation or disclosure.
3. Verify provider and orchestrator defaults at the pinned version. Do not assume a public IP, a reachable metadata service, a permissive firewall, or an absent admission policy.
4. Read and reason over templates and policy; do not render with tools that fetch remote modules or contact any cloud API.
5. Show the change introduced or exposed it.
```
