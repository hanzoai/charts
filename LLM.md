# Hanzo Charts

Helm charts for Hanzo services. Charts are the shape; the values that run
production live in `hanzo/universe`. Every chart publishes to
`oci.hanzo.ai/charts` by version, once.

| Chart | What it deploys |
|-------|-----------------|
| `app` | The one application chart: a container, its Service, and what every service needs — ingress route, PDB, HPA, probes, KMS-backed secrets. Nearly every Hanzo service runs from it with a values file. |
| `iam` | Hanzo IAM, one binary on an embedded store; `store.backend` selects sqlite, sql or datastore (hanzoai/sql over ZAP). |
| `mpc` | Hanzo MPC node. |
| `bootnode` | Bootnode API. Its console is a static export served by the ingress, not a container. |
| `net` | The Zero Trust fabric: controller, routers, console. |

Nothing here depends on an external database, cache, queue or secret store.
Data is Hanzo Base (SQLite) embedded in the service, or hanzoai/sql, kv,
datastore and docdb over ZAP; secrets come from Hanzo KMS. Sites are static
builds served by hanzoai/ingress.

```bash
helm install iam oci://oci.hanzo.ai/charts/iam --version 0.2.0
helm template x charts/app -f path/to/values.yaml
```
