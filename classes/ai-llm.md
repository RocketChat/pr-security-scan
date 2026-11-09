# AI, LLM, and agent classes

Adapted from Cloudflare's `AI-AND-LLM.md` (MIT).

## When to use

A language model participates in a trust-sensitive decision in the changed code: prompt assembly from untrusted input, RAG or persistent memory, tool-calling agents, MCP servers or clients, or code that consumes model output and acts on it. The data flow that matters is untrusted content, to model or memory, to capability, authority, or sink. Transport, access control, queries, files, and rendering remain ordinary boundaries covered by `core.md`.

## Core discipline

```
- Prompt injection alone is not a finding. Require a code-level boundary failure: content reaching another principal's context, invoking authority the requester lacks, disclosing data they cannot read, or driving a sink they cannot reach directly.
- Model output, memory, tool descriptions, and MCP responses are untrusted inputs. Point to the code that grants authority, trusts output, writes durable state, or feeds a sink.
- A guardrail prompt is not a security boundary. Count only deterministic checks, resource-scoped authorization, isolation, binding, and constrained credentials.
- State the attacker, affected principal, effective execution identity, resource, exact action, authority used, and observable impact. A direct, intentional request to use the requester's own authority is not a delegation defect merely because a model runs it.
- Authorization and action binding are separate. Attacker-controlled content that causes an action under a victim's valid authority is an action-binding failure when the victim did not intentionally request or approve that exact action.
- Provider, model, deployment, and renderer behavior not in the repository are exact unknowns.
```

## Context, retrieval, memory
- **Indirect injection**: an attacker can write a RAG document, page, file, email, issue body, or tool response that enters a different principal's context. Trace who writes each source, how retrieval scopes it, whose session consumes it, and what capability is enabled there. The defect is a missing deterministic control, not persuasive text.
- **Context bleed**: history, embeddings, retrieval results, or prompt caches keyed too broadly. Verify tenant and ACL filters in the query itself and every cache key.
- **Memory poisoning**: attacker-controlled content or model summaries written into memory that later shapes another task, user, or privileged session. Memory a user saved for their own allowed requests is not cross-boundary.
- **Role and provenance confusion**: untrusted text impersonating a system message, prior turn, tool result, or memory record through string concatenation or untyped history, and changing a deterministic trust decision.

## Tools and actions
- **Tool-argument injection**: model-produced arguments reaching SQL, shell, file, URL fetch, or privileged APIs without handler-side validation. A schema narrows shape; it does not establish authorization, safe paths, or safe URLs.
- **Excessive agency / confused deputy**: the agent uses a service identity or broad credential while the handler does not re-check the requester's permission on the named resource. A shared credential with enforced per-user query scope is not a defect.
- **Action-confirmation and approval binding**: approval of one described action while execution can use changed arguments, resource, principal, or a later turn; retries and resumes mutating or duplicating a side effect.
- **Schema and dispatcher disagreement**: aliases, extra fields, duplicate keys, or coercions interpreted differently by schema, dispatcher, and handler.
- **Unbounded delegated loops**: a bounded request enqueueing repeated spend, send, or mutation without budget, per-action authorization, cancellation, or idempotency. Reason from code-level accounting.

## MCP and sub-agents
- **Trust inheritance**: a delegated task getting the full session, credentials, memory, or capabilities instead of least authority; delegated results treated as trusted on return.
- **Server and tool identity confusion**: routing by attacker-influenceable server names, tool names, request IDs, or URIs instead of the authenticated connection and outstanding request.
- **Metadata as policy**: tool descriptions, resource metadata, or schemas supplied by an MCP peer trusted as authorization.

## Output and disclosure
- **Insecure output rendering**: model output reaching an executing HTML, Markdown, template, URL, or command sink without the sink's encoding and policy.
- **Sensitive context extraction**: the assembled context containing credentials, another user's data, or policy values that grant access, with user-influenced output exposing them. Disclosure of generic instructions that does not cross a data boundary is not a finding.

## Validation rules

```
1. Name the crossed boundary and observable result: attacker, affected principal or shared resource, execution identity, target, and the unauthorized or unrequested action or disclosure.
2. For confused-deputy claims, show the tool lacks requester-and-resource authorization and that the attacker cannot perform the action normally. For action-binding claims, show attacker-controlled content caused an action under the affected principal's authority that the principal did not intentionally request or approve.
3. For memory or retrieval claims, cite both the attacker-controlled write and the later cross-principal read or privileged decision.
4. For MCP identity claims, verify the authenticated connection, request correlation, tool namespace, and effective credential.
5. Show the change introduced or exposed it.
```
