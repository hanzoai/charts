# Hanzo Charts

Helm charts for Hanzo services. A chart is the shape; the values that run
production live in `hanzo/universe`. Each chart publishes to
`oci.hanzo.ai/charts` by version, once.

| Chart | What it deploys |
|-------|-----------------|
| `iam` | Hanzo IAM, one binary on an embedded store. `store.backend` selects `sqlite` (a kept volume), `sql` or `datastore` (hanzoai/sql over ZAP). |
| `mpc` | Hanzo MPC node. |
| `bootnode` | The bootnode API. Its console is a static export the ingress serves, not a container. |
| `net` | The Zero Trust fabric: controller, routers, console. |

The application chart lives in `hanzo/universe` at `charts/app`, and stays
there: the fleet renders it from that path, and universe already publishes it
to `oci.hanzo.ai/charts`. One chart, one publisher. Moving it here means
universe stops publishing it in the same change, not before.

Nothing here depends on an external database, cache, queue or secret store.
Data is Hanzo Base (SQLite) embedded in the service, or hanzoai/sql, kv,
datastore and docdb over ZAP; secrets come from Hanzo KMS; ingress is
hanzoai/ingress. Images are pinned — a floating tag is not a deployable pin.

```bash
helm install iam oci://oci.hanzo.ai/charts/iam --version 0.2.0
helm template x charts/iam --set store.backend=sql --set store.sqlAddr=sql.hanzo.svc:9653
```
