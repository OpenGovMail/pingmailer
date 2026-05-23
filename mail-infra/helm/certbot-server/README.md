# certbot-server Helm chart

Helm chart for the `ghcr.io/lsflk/silver-certbot` service used by the
Pingmailer / Silver Mail stack to obtain and renew Let's Encrypt
certificates.

This chart is the Kubernetes equivalent of the `certbot-server` block in the
repo-root `docker-compose.yml`:

```yaml
certbot-server:
  image: ghcr.io/lsflk/silver-certbot:main
  volumes:
    - ./mail-infra/services/silver-config/certbot/keys/etc:/etc/letsencrypt
    - ./mail-infra/services/silver-config/certbot/keys/log:/var/log/letsencrypt
    - ./mail-infra/services/silver-config/certbot/keys/lib:/var/lib/letsencrypt
  ports:
    - "80:80"
    - "443:443"
```

## What it deploys

- A `Deployment` running the certbot-server image (single replica,
  `Recreate` strategy since cert state is on RWO volumes).
- A `Service` exposing ports 80 and 443.
- Three `PersistentVolumeClaim`s mirroring the docker-compose bind mounts:
  - `<release>-etc` → `/etc/letsencrypt`
  - `<release>-lib` → `/var/lib/letsencrypt`
  - `<release>-log` → `/var/log/letsencrypt`
- An optional `Ingress` (disabled by default).
- An optional `Secret` for DNS-provider credentials or other sensitive env
  vars (only created when you actually pass `secret.*` values, or you can
  reference an existing one via `existingSecret`).

## Sensitive values

Nothing sensitive lives in `values.yaml`. Pass these at `helm upgrade` time:

| Key                          | Required | Notes                                                  |
|------------------------------|----------|--------------------------------------------------------|
| `letsencrypt.domain`         | yes      | Primary domain for the certificate                     |
| `letsencrypt.email`          | yes      | ACME contact email                                     |
| `letsencrypt.additionalDomains` | no    | Comma-separated SANs                                   |
| `letsencrypt.staging`        | no       | `true` to use LE staging (recommended for first run)   |
| `existingSecret`             | no       | Name of a pre-existing `Secret` to mount as `envFrom`  |
| `secret.<key>`               | no       | If set, chart creates a Secret with these `stringData` |

## Install / upgrade

```bash
helm upgrade --install certbot-server ./mail-infra/helm/certbot-server \
  --namespace pingmailer --create-namespace \
  --set letsencrypt.domain=mail.example.com \
  --set letsencrypt.email=admin@example.com \
  --set letsencrypt.staging=false
```

With DNS-01 credentials via an existing Secret:

```bash
kubectl -n pingmailer create secret generic certbot-dns \
  --from-literal=CLOUDFLARE_API_TOKEN=xxxxx

helm upgrade --install certbot-server ./mail-infra/helm/certbot-server \
  --namespace pingmailer \
  --set letsencrypt.domain=mail.example.com \
  --set letsencrypt.email=admin@example.com \
  --set existingSecret=certbot-dns
```

Or have the chart create the Secret for you (still passed at the CLI, not
committed to `values.yaml`):

```bash
helm upgrade --install certbot-server ./mail-infra/helm/certbot-server \
  --set letsencrypt.domain=mail.example.com \
  --set letsencrypt.email=admin@example.com \
  --set secret.CLOUDFLARE_API_TOKEN=xxxxx
```

## Uninstall

```bash
helm uninstall certbot-server -n pingmailer
```

PVCs are kept on uninstall to preserve the issued certificates. Delete them
explicitly if you want a clean slate:

```bash
kubectl -n pingmailer delete pvc -l app.kubernetes.io/instance=certbot-server
```

## Sharing certs with other workloads

The issued certs live on the `<release>-etc` PVC at `/etc/letsencrypt`. Mount
that PVC read-only into the smtp-server / api-server pods (or run an init
container that copies them out) — the same way the docker-compose stack
shares the host bind mount across `smtp-server` and `api-server`.
