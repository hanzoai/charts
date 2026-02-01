# Hanzo Helm Charts

Official Helm charts for all Hanzo services and infrastructure.

## Charts

| Chart | Description | Version |
|-------|-------------|---------|
| `hanzo-iam` | Identity and Access Management | 0.1.0 |
| `hanzo-kms` | Key Management Service | 0.1.0 |
| `hanzo-mpc` | Multi-Party Computation | 0.1.0 |
| `hanzo-gateway` | API Gateway | 0.1.0 |
| `hanzo-platform` | Developer Platform (GitOps) | 0.1.0 |
| `hanzo-console` | Admin Console UI | 0.1.0 |
| `hanzo-commerce` | Multi-tenant Commerce | 0.1.0 |
| `hanzo-analytics` | Analytics Service | 0.1.0 |
| `hanzo-storage` | Object Storage (S3-compatible) | 0.1.0 |
| `hanzo-bootnode` | Blockchain Infrastructure | 0.1.0 |
| `hanzo-cloud` | Hanzo Cloud Operator | 0.1.0 |
| `hanzo-gitops` | GitOps CI/CD (Tekton-based) | 0.1.0 |
| `hanzo-agents` | AI Agent Orchestration | 0.1.0 |
| `hanzo-llm` | LLM Serving Infrastructure | 0.1.0 |

## Installation

### Add the Hanzo Helm repository

```bash
helm repo add hanzo https://charts.hanzo.ai
helm repo update
```

### Install a chart

```bash
# Install IAM
helm install hanzo-iam hanzo/iam --namespace hanzo --create-namespace

# Install full stack
helm install hanzo-stack hanzo/cloud --namespace hanzo --create-namespace
```

## Configuration

Each chart has its own `values.yaml` with configurable options. See individual chart READMEs for details.

### Common Configuration

All charts support these common values:

```yaml
global:
  domain: hanzo.ai
  imageRegistry: ghcr.io/hanzoai
  storageClass: do-block-storage

  # TLS
  tls:
    enabled: true
    issuer: letsencrypt-prod

  # Database
  database:
    host: postgres.hanzo.svc
    port: 5432

  # Cache
  cache:
    host: redis.hanzo.svc
    port: 6379
```

## Development

### Prerequisites

- Kubernetes 1.25+
- Helm 3.12+

### Testing

```bash
# Lint all charts
helm lint charts/*

# Template a chart
helm template test charts/iam --debug

# Install with dry-run
helm install test charts/iam --dry-run --debug
```

## License

Apache 2.0
