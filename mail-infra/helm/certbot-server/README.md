# opengovmail-certificates Helm chart

Renders [cert-manager](https://cert-manager.io) `Certificate` CRDs for the
OpenGovMail stack. Each configured domain gets a certificate
covering `domain` and `*.domain`, issued by a Let's Encrypt ClusterIssuer via
the Cloudflare DNS-01 solver.

This chart replaces the old `certbot-server` container approach. It does **not**
run a workload — it only declares `Certificate` resources. cert-manager
reconciles them and writes the resulting TLS material into Kubernetes Secrets
that your other workloads (smtp-server, api-server, etc.) mount.

Modeled after [OpenGovMail/opengovmail#325](https://github.com/OpenGovMail/opengovmail/pull/325).

## Architecture

```
 ┌─────────────────────────┐    creates    ┌──────────────────────────┐
 │ opengovmail-certificates     │ ───────────▶  │ Certificate (per domain) │
 │ Helm chart              │               └────────────┬─────────────┘
 └─────────────────────────┘                            │ reconciled by
                                                        ▼
 ┌─────────────────────────┐    refers to   ┌──────────────────────────┐
 │ ClusterIssuer           │ ◀───────────   │ cert-manager             │
 │ (le-staging / le-prod)  │                └────────────┬─────────────┘
 └────────────┬────────────┘                             │ DNS-01 via
              │                                          ▼
              │                              ┌──────────────────────────┐
              └────────── uses ────────────▶ │ Cloudflare API           │
                                             │ (api-token Secret)       │
                                             └──────────────────────────┘
```

## Prerequisites (one-time, per cluster)

These steps are **not** managed by this chart.

### 1. Install cert-manager

```bash
helm install cert-manager oci://quay.io/jetstack/charts/cert-manager \
  --version v1.20.0 \
  --namespace cert-manager --create-namespace \
  --set crds.enabled=true
```

Verify:

```bash
kubectl get pods -n cert-manager   # all pods Running
```

### 2. Bootstrap ClusterIssuers and Cloudflare token

```bash
bash mail-infra/scripts/cert-manager-bootstrap.sh
```

The script prompts for your domain, Let's Encrypt email, and Cloudflare API
token (Zone:Read + DNS:Edit on your zone). It creates:

- `cloudflare-api-token` Secret in the `cert-manager` namespace
- `le-staging` ClusterIssuer (Let's Encrypt staging — untrusted, no rate limits)
- `le-prod` ClusterIssuer (Let's Encrypt prod — trusted, **5 certs/domain/week**)

Verify:

```bash
kubectl get clusterissuer   # le-staging + le-prod with READY=True
```

## Install / upgrade

Sensitive values stay out of `values.yaml`. Pass them on the command line:

```bash
helm upgrade --install opengovmail-certificates ./mail-infra/helm/certbot-server \
  --namespace opengovmail --create-namespace \
  --set tls.issuer=le-staging \
  --set 'tls.domains={mail.example.com,example.com}'
```

When the staging certificate reports `READY=True`, flip to prod:

```bash
helm upgrade --install opengovmail-certificates ./mail-infra/helm/certbot-server \
  --namespace opengovmail --reuse-values \
  --set tls.issuer=le-prod
```

Track issuance:

```bash
kubectl -n opengovmail get certificate
kubectl -n opengovmail describe certificate mail-example-com-tls
```

## Values

| Key                | Default      | Description                                                                 |
|--------------------|--------------|-----------------------------------------------------------------------------|
| `tls.enabled`      | `true`       | When false, no Certificates are rendered                                    |
| `tls.issuer`       | `le-staging` | ClusterIssuer name (`le-staging` or `le-prod`)                              |
| `tls.renewBefore`  | `720h`       | How long before expiry cert-manager renews                                  |
| `tls.domains`      | `[]`         | **Required.** List of apex domains; each gets a cert for `d` and `*.d`      |

`tls.domains` is intentionally empty in `values.yaml` — the chart `fail`s
fast if you forget to pass it.

## Consuming the certificates

For each domain `d`, cert-manager writes a Secret named `<dash-d>-tls` (e.g.
`mail.example.com` → `mail-example-com-tls`) containing `tls.crt` and `tls.key`.
Mount it into your workloads:

```yaml
volumeMounts:
  - name: tls
    mountPath: /certs
    readOnly: true
volumes:
  - name: tls
    secret:
      secretName: mail-example-com-tls
```

## Uninstall

```bash
helm uninstall opengovmail-certificates -n opengovmail
```

This removes the `Certificate` objects. cert-manager will then garbage-collect
the underlying Secrets unless `Certificate.spec.secretTemplate` overrode the
default behaviour. The ClusterIssuers and Cloudflare token Secret remain (they
are cluster-scoped infra installed by the bootstrap script).
