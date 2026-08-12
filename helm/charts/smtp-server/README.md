# pingmailer-smtp Helm chart

Helm chart for the Postfix-based SMTP server (`ghcr.io/opengovmail/pingmailer-smtp`) —
the Kubernetes counterpart of the `smtp-server` block in this repo's
[docker-compose.yml](../../../docker-compose.yml).

This is the third of four Pingmailer mail-plane charts. Install order:

1. [pingmailer-certificates](../certbot-server/) — issues TLS certs via cert-manager.
2. [pingmailer-opendkim](../opendkim-server/) — DKIM milter on `:8891`.
3. [pingmailer-raven-sasl](../raven-sasl-server/) — SASL auth daemon on `:12345`.
4. **pingmailer-smtp** (this chart) — Postfix on `:25` (+ optional submission `:587`).

## What this chart deploys

- A `ConfigMap` that templates `main.cf`, `master.cf`, `pingmailer.yaml`, and
  `recipient_access` from your values. The docker-compose flow renders
  these via a host-side `gen-postfix-conf.sh`; the chart does it in Helm.
- A `Deployment` whose **init container**:
  - seeds an `emptyDir` with the image's stock `/etc/postfix/` contents
    (`postfix-script`, `postfix-files.d`, `dynamicmaps.cf.d`, …),
  - overlays the four rendered configs,
  - runs `postmap recipient_access` so Postfix can read the compiled
    lookup table (this is the step the docker-compose flow does *after*
    container start via `docker exec` — we move it pre-start where it
    belongs).
- A main container that runs the stock image entrypoint (`service postfix
  start && sleep infinity`).
- A `Service` on port 25 (SMTP). Port 587 (submission, STARTTLS-enforced)
  is added when `postfix.submission.enabled=true` (the default).
- A `PersistentVolumeClaim` for `/var/spool/postfix` — the mail queue
  must survive pod restarts so in-flight messages aren't dropped.
- An optional TLS `Secret` mount: when `tlsSecret.name` is set, the chart
  remaps a cert-manager-managed Secret's `tls.crt` / `tls.key` keys to
  `fullchain.pem` / `privkey.pem` and mounts them at
  `/etc/letsencrypt/live/<domain>/` — exactly where Postfix's `main.cf`
  expects to find them.

What this chart **does not** do vs. docker-compose:

- `/var/log` is not a persistent volume. Logs are redirected to
  `/dev/stdout` (`maillog_file = /dev/stdout` in `main.cf`) so
  `kubectl logs` works.
- The "shared SQLite database at `/app/data/databases/shared.db`" referenced
  in the image's entrypoint is not actually shared between containers in
  the original docker-compose either (no volume mount on the `smtp-server`
  service), so the chart does not provision one. Mail flow does not depend
  on it; the entrypoint simply warns.

## Install

Sensitive values stay out of `values.yaml`:

```yaml
# my-smtp-values.yaml
domain: mail.example.com
tlsSecret:
  name: mail-example-com-tls    # produced by the pingmailer-certificates chart
```

```bash
helm upgrade --install smtp-server ./helm/charts/smtp-server \
  --namespace pingmailer --create-namespace \
  -f my-smtp-values.yaml
```

The chart `fail`s with a clear message if `domain` is missing, or if
`postfix.submission.enabled=true` but no `tlsSecret.name` is provided (port
587 enforces STARTTLS — running submission without certs would be broken).

## Exposing to the internet

This chart defaults to **`service.type: ClusterIP`** because:

- LoadBalancers may incur cloud costs / require a provider.
- Mail can be fronted by an external TCP LB or HAProxy you already manage.
- ClusterIP installs cleanly in any cluster without extra requirements.

> **A Route / Ingress will not work for SMTP.** OpenShift Routes and k8s
> Ingress only carry HTTP/HTTPS/TLS-SNI on 80/443. Submission (587) starts in
> plaintext and upgrades with STARTTLS — there is no SNI for the router to key
> on — so raw 25/587 must be exposed with a `LoadBalancer` or `NodePort`.

**Option A — LoadBalancer** (real `:25`/`:587` on a dedicated IP; needs a cloud
L4 LB or MetalLB — stays `<pending>` on bare clusters with no provider):

```yaml
service:
  type: LoadBalancer
  loadBalancerIP: 203.0.113.5            # optional, depends on provider
  loadBalancerSourceRanges: []           # optional CIDR allow-list
  externalTrafficPolicy: Local           # preserve client IP for rate limits
  annotations: {}                        # e.g. GKE / EKS / AKS L4 LB annotations
```

**Option B — NodePort** (fallback when no LB provider exists; exposes high
ports on every node IP — have the platform team open the firewall / NAT
`587 -> nodePort`):

```yaml
service:
  type: NodePort
  externalTrafficPolicy: Local
  nodePorts:
    smtp: 30025
    submission: 30587
```

Then publish DNS (point at the LB IP, or a node/edge IP for NodePort):

```
mail.example.com.   A    203.0.113.5
example.com.        MX   10  mail.example.com.
```

Test the external listener:

```bash
openssl s_client -starttls smtp -connect <external-ip>:587
```

Outbound port 25 is blocked by most cloud providers and ISPs by default —
plan to use a relay (Mailgun, SES, SendGrid) for outbound, or open a
support case to unblock 25.

## Values

| Key                                    | Default                                   | Notes                                                  |
|----------------------------------------|-------------------------------------------|--------------------------------------------------------|
| `domain`                               | `""` (**required**)                       | Primary mail domain                                    |
| `hostname`                             | `""` → `mail.<domain>`                    | `myhostname` in `main.cf`                              |
| `tlsSecret.name`                       | `""` (required when submission enabled)   | cert-manager Secret name                               |
| `tlsSecret.alreadyRenamed`             | `false`                                   | `true` if Secret already uses fullchain.pem/privkey.pem |
| `postfix.submission.enabled`           | `true`                                    | Enables `:587` STARTTLS submission                     |
| `postfix.milters`                      | `["inet:opendkim-server:8891"]`           | Inbound smtpd milters                                  |
| `postfix.submissionMilters`            | `["inet:opendkim-server:8891"]`           | Submission milters (add rspamd here when deployed)     |
| `postfix.sasl.path`                    | `inet:raven-sasl:12345`                   | Where Postfix reaches the SASL daemon                  |
| `postfix.tls.securityLevel`            | `may`                                     | `may` opportunistic / `encrypt` required               |
| `postfix.recipientAccess.rejectAtDomain` | `true`                                  | Mirrors docker-compose: REJECT mail to `@<domain>`     |
| `postfix.maillogFile`                  | `/dev/stdout`                             | Set to `/var/log/mail.log` for legacy file logging     |
| `persistence.spool.size`               | `1Gi`                                     | Postfix queue                                          |
| `replicaCount`                         | `1` (**do not change**)                   | Singleton — PVC is RWO and the queue is single-writer  |
| `service.type`                         | `ClusterIP`                               | `LoadBalancer` or `NodePort` to expose externally      |
| `service.loadBalancerSourceRanges`     | `[]`                                      | CIDR allow-list for a LoadBalancer (empty = open)      |
| `service.externalTrafficPolicy`        | `""`                                      | `Local` preserves client source IP (LB/NodePort)       |
| `service.nodePorts.smtp` / `.submission` | `""`                                    | Pin NodePort numbers (30000-32767) when `type=NodePort`|

## Uninstall

```bash
helm uninstall smtp-server -n pingmailer
```

The spool PVC is preserved (in-flight mail). Delete it explicitly to
discard queued messages.
