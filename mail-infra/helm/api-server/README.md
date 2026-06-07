# silver-api-server Helm chart

Helm chart for the Pingmailer **api-server** — the public HTTP entry point
for sending mail through the Silver stack. The Kubernetes counterpart of
the `api-server` service in [docker-compose.yml](../../../docker-compose.yml).

**Platform support:** This chart is portable across **vanilla Kubernetes** (EKS, GKE, AKS, etc.) and **OpenShift**, with OpenShift-specific features available as optional feature toggles.

## What this chart does

- Runs `api-server` (built from [api-server/Dockerfile](../../../api-server/Dockerfile)) as an unprivileged user (UID/GID 1000), drop-all capabilities, read-only root filesystem.
- **Serves plain HTTP** on container port 8000 (configurable). TLS termination is handled by your ingress/route, not in-pod.
- Service defaults to `type: ClusterIP` for maximum compatibility — external access is configured via `Ingress` (Kubernetes) or `Route` (OpenShift).
- **Optional Ingress** (enabled by default) for standard Kubernetes clusters — configure with your chosen ingress controller (NGINX, Traefik, etc.).
- **Optional OpenShift Route** (disabled by default) for OpenShift users — can be enabled in `values.yaml`.
- `PodDisruptionBudget` when `replicaCount >= 2`.
- HTTP liveness/readiness probes against `GET /healthcheck` (TLS-agnostic).

The chart `fail`s loudly when `image.repository` is missing.

## What it does NOT do

- **It does not build the image.** The api-server has no published image —
  you must build and push to a registry your cluster can pull from. See
  "Build & publish the image" below.
- It does not validate Bearer tokens. The Go code passes the
  `Authorization: Bearer <token>` header straight through to SMTP as the
  XOAUTH2 credential. `oauth2IntrospectUrl` is exposed as an env var for
  forward-compatibility only.
- It does not wire the api-server to the SMTP server. The client picks
  `smtp_host` / `smtp_port` per request in the JSON body.

## Build & publish the image

The api-server has only `api-server/Dockerfile`; no GitHub Actions workflow
publishes it yet. Pick one path:

**GHCR (recommended for real clusters):**

```bash
cd api-server
docker build -t ghcr.io/<your-org>/pingmailer-api-server:0.1.0 .
echo $GITHUB_TOKEN | docker login ghcr.io -u <your-user> --password-stdin
docker push ghcr.io/<your-org>/pingmailer-api-server:0.1.0
cd ..
```

**Minikube local image (for development):**

```bash
# Build inside minikube's Docker daemon so the cluster can pull it
# without going through an external registry.
eval $(minikube docker-env)
docker build -t pingmailer-api-server:dev ./api-server
eval $(minikube docker-env -u)

# Then in your values overlay:
#   image:
#     repository: pingmailer-api-server
#     tag: dev
#     pullPolicy: Never        # local image, never try to pull
```

## Install

### Default (Kubernetes with Ingress)

This is the recommended setup for portable deployment.

```yaml
# my-api-values.yaml
image:
  repository: "ghcr.io/<your-org>/pingmailer-api-server"
  tag: "0.1.0"

ingress:
  enabled: true
  className: "nginx"                      # your ingress controller
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
  hosts:
    - host: mail.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: mail-example-com-tls
      hosts:
        - mail.example.com

oauth2IntrospectUrl: "https://thunder.example.com/oauth2/introspect"
```

```bash
helm upgrade --install api-server ./mail-infra/helm/api-server \
  --namespace pingmailer --create-namespace \
  -f my-api-values.yaml
```

### OpenShift Setup

To deploy on OpenShift and use OpenShift Route:

```yaml
# my-api-values-openshift.yaml
image:
  repository: "ghcr.io/<your-org>/pingmailer-api-server"
  tag: "0.1.0"

ingress:
  enabled: false                   # use Route instead

route:
  enabled: true
  host: "mail.example.com"         # (optional) leave empty for auto-generated
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect

oauth2IntrospectUrl: "https://thunder.example.com/oauth2/introspect"
```

```bash
helm upgrade --install api-server ./mail-infra/helm/api-server \
  --namespace pingmailer --create-namespace \
  -f my-api-values-openshift.yaml
```

---

Once deployed, verify the ingress or route:

```bash
# Kubernetes
kubectl -n pingmailer get ingress
# Update DNS A-record to point at the ingress controller's IP

# OpenShift
oc -n pingmailer get route api-server
# Router automatically handles DNS (or configure your external DNS)
```

## Public exposure: Kubernetes vs OpenShift

This chart prioritizes **Kubernetes-first portability** while offering **optional OpenShift support**. Choose one:

### For Kubernetes Clusters

**Recommended: Ingress (default, `ingress.enabled: true`)**

Use your cluster's ingress controller (NGINX, Traefik, Istio, etc.) to terminate TLS and route traffic to the plain-HTTP service.

```yaml
# my-api-values.yaml
ingress:
  enabled: true
  className: "nginx"                # or your controller
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
  hosts:
    - host: mail.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: mail-example-com-tls
      hosts:
        - mail.example.com

service:
  type: ClusterIP              # default; cluster-internal only
```

**Alternative: LoadBalancer Service (no ingress controller required)**

If your cloud provider supports LoadBalancer (GKE, EKS, AKS), you can skip the ingress:

```yaml
service:
  type: LoadBalancer
  port: 443
  annotations:
    cloud.google.com/neg: '{"ingress": true}'  # GKE example

ingress:
  enabled: false
```

Then provision TLS externally (e.g., load balancer's own cert, or a reverse proxy in front).

### For OpenShift Clusters

**Enable OpenShift Route (`route.enabled: true`)**

OpenShift's built-in router handles TLS termination and routing. This is optional and disabled by default to keep the chart portable.

```yaml
route:
  enabled: true
  host: "mail.example.com"       # (optional) custom host; leave empty for default router hostname
  tls:
    termination: edge            # (or reencrypt, passthrough)
    insecureEdgeTerminationPolicy: Redirect

ingress:
  enabled: false                 # Route replaces Ingress on OpenShift
```

---

| Scenario | Setup | Service type | Ingress | Route |
|---|---|---|---|---|
| **Kubernetes + cloud LB** | GKE, EKS, AKS | `LoadBalancer` | `false` | N/A |
| **Kubernetes + ingress controller** | On-prem, self-managed | `ClusterIP` | `true` | N/A |
| **OpenShift (optional TLS)** | Any OpenShift | `ClusterIP` | `false` | `true` |
| **Mixed multi-platform** | Same chart deployed to both | `ClusterIP` | `true` | `true` |


## Values

### Core Configuration

| Key | Default | Notes |
|---|---|---|
| `image.repository` | `""` (**required**) | Your registry path, e.g. `ghcr.io/silver-mail-platform/pingmailer-api-server` |
| `image.tag` | `latest` | Pin to a real version in production |
| `containerPort` | `8000` | Port the Go server listens on inside the pod |
| `replicaCount` | `2` | API server is stateless — scale freely |

### Service & Network

| Key | Default | Notes |
|---|---|---|
| `service.type` | `ClusterIP` | Kubernetes-native default; routes via Ingress or Route |
| `service.port` | `8000` | Service port (same as containerPort in this setup) |

### Ingress (Kubernetes)

| Key | Default | Notes |
|---|---|---|
| `ingress.enabled` | `true` | Enable for Kubernetes clusters; disable for OpenShift-only |
| `ingress.className` | `""` | Your ingress controller, e.g. `nginx`, `traefik` |
| `ingress.annotations` | `{}` | Add `cert-manager.io/cluster-issuer`, provider-specific settings, etc. |
| `ingress.hosts` | `[]` | List of hostnames; see `values.yaml` for structure |
| `ingress.tls` | `[]` | TLS certificate configuration |

### OpenShift Route (OpenShift only)

| Key | Default | Notes |
|---|---|---|
| `route.enabled` | `false` | Set `true` only on OpenShift clusters |
| `route.host` | `""` | Hostname (optional; OpenShift router assigns default if empty) |
| `route.tls.termination` | `edge` | `edge` (default), `reencrypt`, or `passthrough` |
| `route.tls.insecureEdgeTerminationPolicy` | `Redirect` | `Redirect` (HTTPS only) or `Allow` (HTTP + HTTPS) |
| `route.tls.certificate` | `""` | PEM cert for custom host (optional) |
| `route.tls.key` | `""` | PEM key for custom host (optional) |
| `route.tls.caCertificate` | `""` | PEM CA chain for custom host (optional) |

### Miscellaneous

| Key | Default | Notes |
|---|---|---|
| `oauth2IntrospectUrl` | `""` | Optional, currently unused by the code |
| `existingSecret` | `""` | Name of a pre-existing Secret to `envFrom` (future API keys, etc.) |

## Design Principles & Portability

This chart follows **best practices for open-source Helm charts**:

### 🟢 Kubernetes-First by Default
- **Core chart is platform-agnostic:** It runs on vanilla Kubernetes with zero OpenShift dependencies.
- **Service is ClusterIP:** Routes traffic through standard Kubernetes Ingress (NGINX, Traefik, Istio, etc.).
- **TLS termination is external:** The pod serves plain HTTP; TLS is handled at the ingress or route layer. This decouples the app from infrastructure concerns.

### 🔵 OpenShift Support is Optional
- **Feature-flagged:** Set `route.enabled: true` to use OpenShift Route — nothing else changes.
- **Not mandatory:** OpenShift users *can* use Ingress instead if they prefer; Route is an *option*, not a requirement.
- **No lock-in:** Swapping from Ingress to Route (or vice versa) is a one-line YAML change.

### Why This Matters
- ✅ **Shareable:** Chart works on any Kubernetes cluster (cloud, on-prem, managed).
- ✅ **Maintainable:** No platform-specific code paths in the core logic.
- ✅ **Flexible:** Teams choose their infrastructure (cloud LB, Ingress controller, OpenShift).
- ✅ **Industry standard:** This pattern is used by production Helm charts (PostgreSQL, Redis, Kafka, etc.).

## Uninstall

```bash
helm uninstall api-server -n pingmailer
```

Nothing persistent is created by this chart — uninstall is clean.
