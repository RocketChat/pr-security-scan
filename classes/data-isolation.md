# Data isolation and lifecycle classes

Adapted from Cloudflare's `DATA-ISOLATION-AND-LIFECYCLE.md` (MIT).

## When to use

The diff touches multi-tenant or access-controlled data: queries and models, caches, search indexes, object storage links, analytics and logs, export/import/backup/restore, migrations, or deletion and revocation. Endpoint-level access control belongs to `core.md`; this file follows one data item through every copy and state transition.

## Core discipline

```
- A tenant or owner field on a record is not isolation. Find the query, key, path, policy, or row-level control that enforces it for each read and write path.
- Trace derived copies. Sanitized primary data can be unsafe in search, cache, analytics, export, previews, logs, replicas and backups with different ACL and retention rules.
- Deletion and revocation are lifecycle contracts. Check current, historical, cached, indexed, exported, restored and queued copies within the product's stated boundary.
- A privacy or retention preference is not automatically a security vulnerability. Require an explicit data-access boundary or deletion/revocation guarantee and an unauthorized reader or later operation.
- Hosted storage policy, CDN behavior, replica lag, retention and backup access are usually not in the repository. Return them as exact unknowns.
```

## Tenant and object isolation
- **Missing tenant/owner enforcement**: a read, update, delete, list, count, or bulk query identifying an object without binding it to the authenticated tenant/owner, or trusting body fields to supply it. Compare direct, nested, background, admin, import, and legacy paths.
- **Key and namespace collision**: cache keys, object paths, uniqueness constraints, search IDs, temp files, or dedup keys omitting tenant or environment.
- **Policy and query disagreement**: row-level policy, ORM default scopes, filters, and raw or service clients applying different predicates (joins, aggregates, views, `unscoped` clients, error paths with missing context).
- **Blob and signed-reference overreach**: object keys, attachment IDs, version IDs, shared links, or signed URLs permitting more than the issuer's access or surviving ACL changes.

## Derived data and disclosure
- **Search, cache, and index ACL drift**: a primary record's ACL or lifecycle changing without invalidating a searchable, cached, embedded, thumbnail, or preview copy. Check filtering at retrieval time as well as ingestion.
- **Alternate readers**: private content or credentials emitted into logs, traces, or analytics with broader access, longer retention, or tenant mixing.
- **Enumeration and oracles**: counts, filters, ordering, errors, uniqueness, or timing disclosing protected state. Require a concrete confidential predicate and observable distinction.

## Export, backup, restore, migration
- **Export scope expansion**: an export or report including other tenants, inaccessible fields, soft-deleted data, secret values, or history above the requester's access; authorization to download the final artifact.
- **Import and restore authority**: bypassing owner, schema, ACL, uniqueness, or validation rules; recreating records in a tenant the requester cannot write.
- **Migration defaults**: old records lacking tenant, ACL, or lifecycle fields; dual-read/write and rollback paths applying different defaults.

## Deletion, revocation, lifecycle
- **Soft-delete bypass**: direct lookup, search, relation traversal, link, job, or restore ignoring the lifecycle predicate.
- **Stale authorization**: membership removal, ACL update, or role downgrade not invalidating sessions, caches, subscriptions, jobs, or materialized data.
- **Retention overrun and restore**: queued work, retries, or restores recreating data or permissions that current policy no longer allows.

## Validation rules

```
1. Name the lower-trust principal, the protected data or state, the affected owner/tenant, the alternate copy or operation, and the unauthorized disclosure or mutation.
2. Cite the intended source-of-truth policy and the path that omits or disagrees with it. Confirm no other layer enforces the same condition.
3. If external cache, object storage, replica, analytics, backup or retention policy is required, return an exact unknown.
4. Show the change introduced or exposed it.
```
