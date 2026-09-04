# hanzo/app

One chart for a Hanzo service: a container, a Service, and the things every
service needs — ingress, disruption budget, autoscaling, probes, KMS-backed
secrets. It replaces the `apps.hanzo.ai` CRD and the operator's service profile.

```sh
helm install id oci://oci.hanzo.ai/hanzo/app -f values/hanzo/id.yaml
```

## Why one chart and not 79

The App CRD already proved the fleet has one shape. 74 of 79 App CRs set no
`role` at all — they are image, ports, replicas, env, resources, ingress, probes.
So this is one chart and 79 values files, not 79 charts, and `values.yaml` keys
are the CRD's `spec` keys one for one. An App CR pastes in as values.

## The values contract

`values.schema.json` is the contract, and it is what makes the chart usable from
a UI: platform.hanzo.ai generates typed fields, validation and descriptions from
it rather than showing a YAML textarea. It also catches shape errors at render
time instead of at rollout — it caught two during this migration (a PVC block
read as a size, and a probe carrying two handlers).

Two rules the schema enforces that are worth stating out loud:

- **`additionalProperties: false`.** A typo in a values key is an error, not a
  silently ignored setting.
- **No way to write a secret value.** `kmsSecrets` names a path in KMS; the
  chart has no `stringData` and no plaintext escape hatch. That is what makes a
  values file safe to commit and safe to publish.

## What the operator did implicitly

Four behaviours were invisible in the App CRs and had to be carried across, or
they would have disappeared with the operator:

| Behaviour | Why it matters |
|---|---|
| Flat `{path, port}` expanded to `httpGet`/`tcpSocket` | 45 services. Without it, no probe is valid and every one stops working. |
| A TCP readiness probe synthesized when none is declared | ~30 services. Without it a pod is ready before it can serve, and a rolling update drops requests. |
| `topologySpreadConstraints` only above one replica | Spreading one replica constrains nothing; emitting it anyway is 30 phantom diffs. |
| `persistence` as a macro for PVC + restore initContainer + replicate sidecar + ConfigMap | Four things behind one key. Expanded into the primitives, so the wiring is visible. |

## Migrating a service

`hack/app2values.py --live` converts every App CR. `hack/diff-live.py` renders
each result and compares it against the live object — that is the gate, and it
grades what it finds:

- **BREAKING** — the apiserver would reject the apply. Only a workload's
  `spec.selector` qualifies; it is immutable, which is why the chart's selector
  is exactly the two labels the operator used and must never grow a third.
- **DRIFT** — live differs from what the App CR says. The CR was not the truth.
- **BENIGN** — an intended consequence of moving to Helm, each one listed with
  its reason in `ACCEPTED`.

Current state: **66 clean, 1 needs review, 0 render failures, BREAKING=0**
across the 67 values files. The review item is `dataroom`: its live replicate
init and sidecar carry `AGE_IDENTITY`/`AGE_RECIPIENT` while its `replicate.yml`
has no age stanza, so the running Deployment predates age encryption becoming
opt-in. Unrelated to the chart.

### Cutover

An App CR owns its Deployment with `blockOwnerDeletion: true`, so deleting the
CR garbage-collects the running workload.

**`--cascade=orphan` does not prevent that.** This section used to say it did.
Measured on hanzo-k8s 2026-07-29: `kubectl delete app.hanzo.ai papers -n hanzo
--cascade=orphan` removed the CR *and* Deployment/papers, and papers.hanzo.ai
served 404 until the CR was restored. The operator is not the deleter — its App
controller never calls delete on a workload and registers no finalizer. It is
Kubernetes GC: the orphan policy must strip `ownerReferences` from the
dependents before the owner goes, and here the refs outlived the owner, so the
children resolved to a dead uid and were collected.

So the ownerReference is removed from every child FIRST, and the CR is deleted
only once each child is verified to carry none:

```sh
hack/cutover.sh <namespace> <name>
```

It detaches the children (a metadata-only patch — no pod restart), refuses to
continue if any still references the CR, then drops the file from
`infra/k8s/operator/crs/` and prints the finish order.

**Adoption costs exactly one rolling replacement, and that is not free for
everything.** Measured cutting over `sign`: after the fleet Application synced,
the Deployment went generation 8 -> 9 and a new ReplicaSet appeared. The pod
templates differ in ONE key —

    app.kubernetes.io/managed-by: hanzo-operator   ->   Helm

— which is in `spec.template.metadata.labels`, so it changes the
pod-template-hash and rolls every pod. `diff-live.py` grades that label BENIGN,
and on object metadata it is; inside the pod template it is a rollout.

For a service on RollingUpdate with `maxUnavailable: 0` this is zero-downtime
and unremarkable (sign served throughout — sign.hanzo.ai kept answering 302 to
esign.hanzo.ai across the roll). It is NOT unremarkable for a singleton on
`Recreate`: **chat is replicas 1 + Recreate + a 600MB image, so adopting it this
way is 2.5-4 minutes of 503.** That is the reason chat goes last, and it needs
either a surge-capable strategy or the fix below first.

The fix that makes adoption genuinely metadata-only is to keep `managed-by` OUT
of the pod template — object metadata can say who manages the object without the
pods inheriting it. Controller identity should not be part of pod identity, or
every future change of manager reschedules the fleet. Doing it costs the same
one roll per service (the label is removed rather than rewritten), so it is
worth doing BEFORE the remaining adoptions rather than after.

**A CR file that carries routing needs the fleet Application to sync in the same
operation.** `crs/sign.yaml` held an App, two IngressRoutes and a Middleware. The
App is deleted by the cutover, but the three routing objects stay live and carry
`apps.hanzo.ai/tracking-id: universe-crs:...`, so delisting them leaves
`universe-crs` OutOfSync on `requiresPruning` — for objects that must NOT be
pruned. Nothing resolves that on its own, because the fleet AppSet has no
`automated` block. Syncing `hanzo-sign` re-stamped all three with
`hanzo-sign:...` and universe-crs returned to Synced/Healthy. So for these
services the sequence has a fourth step, and skipping it parks the whole crs/
Application OutOfSync: values clean -> detach + delete CR -> **sync the fleet
Application** -> verify.

That order matters as much as the detach. `selfHeal` recreates the CR from the
revision CD **last synced**, not from git HEAD, so pushing and deleting in the
same breath is not enough — in the papers incident the CR was restored from a
stale revision seconds after deletion and the operator rebuilt the Deployment
behind it (generation reset 4 → 1). Push the removal, force
`apps.hanzo.ai/refresh=hard`, wait for `.status.sync.revision` to equal the
commit, and only then delete the CR. `universe-crs` runs `prune: false`, so
removing the file deletes nothing by itself; leaving it in place would have
selfHeal recreate the CR and put two writers on one Deployment.

## values-review — what is left

These render differently from live, so they are declared but not enforced.
Nothing globs `values-review/`. Each moves to `values/` when its diff is
understood, and the migration is done when the directory is empty.

**Services whose Service selects nothing** — `bot-gateway`, `hanzo-app`,
`insights-sql`, `status`, `vector`. Each has a hand-written Service selecting
`{app: <name>}`, no pod carries that label, and all five have zero endpoints
today. They were never adopted by the operator. The chart's selector fixes them,
which is a behaviour change: traffic starts flowing where it currently does not.
Worth confirming that is wanted before it happens.

**Services where the CR is ahead of what runs** — the CR was edited and never
reached the cluster, so syncing rolls production forward:

- `chat` — **this reason has expired.** It read "image `v1.0.50` → `sha-1328e8e`,
  and `MEILI_HOST`/`MEILI_MASTER_KEY` become `INDEX_URL`/`INDEX_KEY`". Both
  landed: live runs `INDEX_URL`/`INDEX_KEY` already, and regenerating from the
  current CR renders **clean** (`diff-live.py chat` → BREAKING=0 DRIFT=0). The
  stale `values-review/hanzo/chat.yaml` still pins `sha-1328e8e`, which is
  neither live nor what the CR says — regenerate it before trusting it.
  What blocks chat now is not fidelity, it is the enforcement gap below plus the
  fact that chat is actively shipped through `crs/chat.yaml` (two tag bumps
  landed during this session alone).
- `superbase` — image `0.1.5` → `0.3.4`, plus `fsGroup: 1000` and a PVC.
- `hanzo-playground` — 4 ingress rules → 6, 4 TLS entries → 1.
- `bot-gateway` — port `ws` renamed to `ws-bridge`, which anything dialing the
  port by name has to follow.

**Cosmetic** — `cloud`, `iam`, `hanzo-idv` differ only in stale `part-of` /
`component` labels and empty-string env values. They are safe to move once
someone confirms the labels.

## Enforcement — `cd.automated`, per service

A service passing `diff-live.py` is ready to be *expressed* by the chart. That
is not the same as being *delivered* by it, and conflating the two is what left
cutovers half-done: the tag bump lands in git, CD notices, and production keeps
running the old image. Nothing errors.

Enforcement is now a field in the service's own values file:

```yaml
cd:
  automated: true   # sole writer: no App CR
```

**Default is off.** Without the key an Application reports drift and nothing
moves, which is what all 61 un-migrated services still do.

The AppSet reads it through `templatePatch` — `template` is a typed
ApplicationSpec whose YAML is parsed before any templating, so a conditional
block is only expressible in the patch. The flag lives in the values file rather
than in a `values-enforced/` directory because the directory already IS the
inventory; a second directory would be a second inventory to keep in step, and
moving a file between them would change a service's *name* to change its
*policy*.

### When a service is ready

Not when its diff is small. **When nothing else writes its objects.** The
operator sets `app.kubernetes.io/managed-by: hanzo-operator` on the pod
template; this chart sets `Helm` in the same place. Enable a service that still
has an App CR and two controllers rewrite one pod-template label forever — every
flip a rolling restart. Measured 2026-07-29 on hanzo-k8s: **all 62 OutOfSync
services carried that flip inside `spec.template.metadata.labels`, none on
object metadata alone.** So the check is `kubectl get app <name> -n <ns>`
returning NotFound, and the sequence per service is: values clean → detach +
delete CR → `cd.automated: true`.

Enforced today (all six verified to have no App CR, and to differ from live by
nothing but ownership labels): `blog`, `docs`, `karma-style`, `o11y-site`,
`papers`, `team-docs`.

### The one place the cluster is right and git is not

Across all 67, exactly one field would be **deleted** rather than added:
`Service/postgres` in `sql` carries `hanzo.ai/note: "backward-compat alias for
sql — migrate consumers then remove"`, hand-written and in no values file. It is
a comment, so losing it costs documentation and not traffic — but it is the only
instance fleet-wide of the case that actually matters, where enabling reverts
something only the cluster knows. Put it in `sql.yaml` before enabling `sql`.

Everything else is additive: 62 of 62 OutOfSync services differed only by labels
the chart adds. Zero differed by image, env, replicas or resources, and zero
resources were flagged for pruning — so on this cluster the danger is never what
a sync *writes*, it is who writes it next.

`prune` stays false, matching the rule the generators already carry: this plane
never deletes. `selfHeal` is on, because without it CD acts on a git change and
ignores drift — which is most of what enforcement is for.

## Layout

```
charts/app/
  Chart.yaml  values.yaml  values.schema.json
  templates/          workload, service, ingress, pdb, hpa, kmssecret, observability
  values/<ns>/<name>.yaml         reconciled by the `fleet` ApplicationSet
  values-review/<ns>/<name>.yaml  declared, not enforced
  hack/app2values.py  hack/diff-live.py  hack/cutover.sh
```

The directory is the inventory. `values/hanzo/www.yaml` generates the
Application `www` in namespace `hanzo` — there is no list to keep in step, and
adding a service is adding a file.
