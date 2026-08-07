# silver-opendkim Helm chart

Helm chart for the OpenDKIM milter (`ghcr.io/lsflk/silver-dkim`) — the
Kubernetes counterpart of the `opendkim-server` service in this repo's
[docker-compose.yml](../../../docker-compose.yml).

OpenDKIM signs (and verifies) outbound SMTP traffic from Postfix. This chart:

1. Generates `opendkim.conf`, `KeyTable`, `SigningTable`, `TrustedHosts`, and
   `silver.yaml` deterministically from your `domains` list and packs them
   into a `ConfigMap`.
2. Runs the `silver-dkim` image, which inspects `silver.yaml` on startup and
   calls `opendkim-genkey` for any domain whose private key is not yet on
   disk at `/etc/dkimkeys/<domain>/<selector>.private`.
3. Persists those generated keys on a `PersistentVolumeClaim` so subsequent
   pod restarts reuse the same keys (and therefore the same published DNS
   TXT records).
4. Exposes the Milter protocol on `ClusterIP :8891` so Postfix
   (`smtpd_milters=inet:opendkim-server:8891`) can reach it.

## DKIM key management — the trade-off you're picking

The two mainstream patterns in Kubernetes are:

| Pattern | How | Pros | Cons |
|---|---|---|---|
| **Secret-mount** | Pre-generate the private keys, `kubectl create secret`, mount it at `/etc/dkimkeys` | etcd encryption-at-rest, RBAC-gated, easy to mirror across clusters | Manual bootstrap + manual rotation |
| **PVC-mount (this chart)** | Container self-bootstraps via `opendkim-genkey` on a PVC | Zero-touch — install and forget | Encryption depends on your `StorageClass`; you own backup |

The `silver-dkim` image is **designed for the PVC pattern** — its entrypoint
runs `opendkim-genkey` for any missing key and writes into `/etc/dkimkeys/`.
If you want the Secret pattern instead, point `persistence.existingClaim` at
a CSI Secret-backed PVC (or kustomize-patch the Deployment to mount a
Secret at `/etc/dkimkeys` and skip the PVC altogether).

## Install

Sensitive value (the domain list) is intentionally absent from `values.yaml`.
Supply it on the command line or via a private values file:

```bash
# my-domains.yaml (do not commit)
domains:
  - domain: example.com
    selector: mail
    keySize: 2048
  - domain: another.example.com
    selector: mail-2026
```

```bash
helm upgrade --install opendkim-server ./helm/charts/opendkim-server \
  --namespace pingmailer --create-namespace \
  -f my-domains.yaml
```

Or inline:

```bash
helm upgrade --install opendkim-server ./helm/charts/opendkim-server \
  --namespace pingmailer --create-namespace \
  --set 'domains[0].domain=example.com'
```

The chart `fail`s loudly when `domains` is empty.

## After install: get the DNS TXT records

`opendkim-genkey` writes the public-key TXT record alongside the private key.
The pod prints them on startup; you can also grab them on demand:

```bash
kubectl -n pingmailer exec deploy/opendkim-server -- \
  sh -c 'for d in /etc/dkimkeys/*; do echo "--- $(basename "$d") ---"; cat "$d"/*.txt; done'
```

Publish each at `<selector>._domainkey.<domain>` in your authoritative DNS.

## Wire Postfix to OpenDKIM

In the smtp-server (Postfix) chart / config:

```
smtpd_milters     = inet:opendkim-server:8891
non_smtpd_milters = inet:opendkim-server:8891
milter_default_action = accept
```

The default `fullnameOverride: opendkim-server` in [values.yaml](values.yaml)
keeps the Service DNS short so the docker-compose Postfix `master.cf`
(`-o smtpd_milters=inet:opendkim-server:8891`) works without edits when both
charts share a namespace.

## Values

| Key                          | Default                  | Notes                                                                 |
|------------------------------|--------------------------|-----------------------------------------------------------------------|
| `domains`                    | `[]` (**required**)      | List of `{domain, selector?, keySize?}`. `selector` defaults to `mail`, `keySize` to `2048` |
| `image.repository`           | `ghcr.io/lsflk/silver-dkim` |                                                                       |
| `image.tag`                  | `main`                   |                                                                       |
| `opendkim.mode`              | `sv`                     | `s` = sign only, `v` = verify only, `sv` = both                       |
| `opendkim.trustedHosts`      | RFC1918 + loopback       | Chart appends each configured domain + `*.<domain>` automatically     |
| `service.port`               | `8891`                   |                                                                       |
| `persistence.enabled`        | `true`                   | Set `existingClaim` to bring your own PVC                             |
| `persistence.size`           | `256Mi`                  | RSA-2048 keys are tiny; this is a generous default                    |
| `podSecurityContext.fsGroup` | `999`                    | `opendkim` GID inside the image — needed for PVC writes               |
| `replicaCount`               | `1` (**do not change**)  | DKIM is intrinsically singleton + PVC is RWO                          |

## Rotating a DKIM key

1. Pick a new `selector` (the old DNS record stays live so in-flight mail is still verifiable).
2. Update `domains[i].selector` in your values file.
3. `helm upgrade …` — the new selector triggers `opendkim-genkey` for a fresh key.
4. Publish the new TXT record alongside the old.
5. After your DKIM TTL has lapsed across the internet, delete the old TXT record.

## Uninstall

```bash
helm uninstall opendkim-server -n pingmailer
```

PVC stays behind — see NOTES.txt to delete it explicitly.
