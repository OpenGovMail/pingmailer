# Pingmailer — Helm deployment guide

`helm/` is a single umbrella chart that installs the whole outbound-mail stack
as one release. Each service is still a self-contained subchart under
`charts/`, so you can install the stack as a unit or roll out one service at a
time.

```
helm/
├── Chart.yaml            # umbrella chart, declares the 4 subcharts
├── values.yaml           # defaults + the values you MUST fill in
├── values.example.yaml   # a complete, realistic install to copy from
├── templates/NOTES.txt   # post-install instructions
└── charts/
    ├── api-server/        # Go HTTP relay        :8000
    ├── opendkim-server/   # OpenDKIM milter      :8891
    ├── raven-sasl-server/ # SASL / OAUTHBEARER   :12345  (Service: raven-sasl)
    └── smtp-server/       # Postfix (rootless)   :25 / :587
```

## How the pieces fit together

```
   external caller
        │  HTTPS  (Ingress on Kubernetes, Route on OpenShift)
        ▼
   api-server :8000 ──── SMTP+XOAUTH2 ────┐
                                          ▼
                                    smtp-server :587 / :25
                                          │
                     SASL auth ───────────┼─────────── DKIM signing
                            │                                │
                            ▼                                ▼
              raven-sasl :12345                   opendkim-server :8891
                            │
                            ▼
                  thunder-server :8090   (not in this chart)
```

Postfix addresses the other services by fixed Service DNS names —
`inet:opendkim-server:8891` and `inet:raven-sasl:12345`. Those names are pinned
via `fullnameOverride` in each subchart, so **install all components into the
same namespace** and don't rename them unless you update
`smtp-server.postfix.milters` and `smtp-server.postfix.sasl.path` to match.

## Installing from the chart registry

Released versions are published to GHCR as OCI artifacts, so you can install
without cloning this repo:

```bash
helm show values oci://ghcr.io/silver-mail-platform/charts/pingmailer --version <version> > my-values.yaml
# edit my-values.yaml, then:
helm install pingmailer oci://ghcr.io/silver-mail-platform/charts/pingmailer \
  --version <version> -n <namespace> -f my-values.yaml
```

`helm search` does not work against OCI registries. List available versions with:

```bash
helm show chart oci://ghcr.io/silver-mail-platform/charts/pingmailer --version <version>
```

If the package is private, authenticate first with a token that has
`read:packages`:

```bash
echo $GITHUB_TOKEN | helm registry login ghcr.io -u <username> --password-stdin
```

All four subcharts are vendored into the package, so there are no dependencies
to pull. Everything below applies equally to a registry install and a local
`./helm` install — substitute the OCI URL for the path.

## Prerequisites

| Requirement | Notes |
|---|---|
| Helm 3.8+ and `kubectl` | `helm version` |
| A namespace you can deploy into | any namespace you can create workloads in |
| A TLS Secret for the mail domain | keys `tls.crt` + `tls.key`. Deploy `mail-infra/helm/certbot-server` first, or use cert-manager. Required by `smtp-server` while submission/587 is enabled. |
| Thunder auth server reachable in-cluster | `raven-sasl-server.config.authServerUrl` defaults to `https://thunder-server:8090/...`. Not deployed by this chart. |
| A registry the cluster can pull from | images default to `ghcr.io/silver-mail-platform/*` and `ghcr.io/lsflk/*`. Add `imagePullSecrets` per subchart for a private registry. |
| Two RWO PersistentVolumes | 256Mi for DKIM keys, 1Gi for the Postfix mail queue. |

TLS certificates are deliberately **not** part of this chart — certificate
issuance has its own lifecycle. Deploy `certbot-server` (still under
`mail-infra/helm/certbot-server`) or cert-manager separately, then point
`smtp-server.tlsSecret.name` and `raven-sasl-server.tlsSecret.name` at the
Secret it produces.

## Deploy

### 1. Create your values file

Never edit `values.yaml` in-tree — it holds defaults and no secrets. Copy the
example and fill it in:

```bash
cp helm/values.example.yaml my-values.yaml   # add my-values.yaml to .gitignore
```

Replace every `example.com` and `your-mail-app-client-id` placeholder. These
values are **required** — the charts fail at render time (with a readable
message) if any is missing:

| Value | What it is |
|---|---|
| `smtp-server.domain` | primary mail domain, e.g. `example.com` |
| `smtp-server.tlsSecret.name` | Secret with `tls.crt` / `tls.key` |
| `opendkim-server.domains[]` | one entry per signing domain (`domain`, optional `selector`, `keySize`) |
| `raven-sasl-server.config.domain` | same mail domain |
| `raven-sasl-server.config.oauth.audience[]` | OAuth client IDs whose tokens are accepted |
| `raven-sasl-server.oauthEmailAuthorization` | client_id → addresses that client may send as |

There is intentionally no `global.domain`: each subchart owns its domain field
so it stays installable on its own. Set the same domain in all three places —
they are marked `### MAIL DOMAIN` in `values.yaml`.

`raven-sasl-server.oauthEmailAuthorization` is sensitive. Keep it in your
uncommitted values file, or supply it separately with a second `-f`.

### 2. Preview

```bash
helm lint ./helm -f my-values.yaml
helm template pingmailer ./helm -n <namespace> -f my-values.yaml | less
```

### 3. Install

```bash
helm upgrade --install pingmailer ./helm \
  --namespace <namespace> --create-namespace \
  -f my-values.yaml
```

See [OpenShift deployment](#openshift-deployment) below for the OpenShift form
of this command and the four constraints that namespace enforces.

### 4. Verify

```bash
kubectl -n <namespace> get pods,svc,pvc -l app.kubernetes.io/instance=pingmailer
kubectl -n <namespace> rollout status deploy/smtp-server
kubectl -n <namespace> logs deploy/smtp-server -f
```

### 5. Publish DNS

OpenDKIM generates the keypair on first start, so this can only happen after
the install. Read the public record out of the pod:

```bash
kubectl -n <namespace> exec deploy/opendkim-server -- \
  cat /etc/dkimkeys/example.com/mail.txt
```

Then publish:

| Record | Value |
|---|---|
| `mail._domainkey.example.com` TXT | the key material printed above |
| `example.com` TXT | `v=spf1 mx a ~all` (adjust to your senders) |
| `_dmarc.example.com` TXT | `v=DMARC1; p=quarantine; rua=mailto:...` |
| `example.com` MX | `10 mail.example.com.` (only if this host receives mail) |

Mail signed before the DKIM TXT record propagates will fail verification at the
recipient.

## OpenShift deployment

Everything below is a real constraint an OpenShift tenant namespace enforces —
each one was hit during an actual install. Substitute your own namespace,
cluster, and domain for the placeholders.

### Log in and select the project

```bash
oc login --server=https://<cluster-api-host>:6443
oc project <namespace>
oc whoami --show-context     # confirm before touching a prod namespace
```

### Install

```bash
helm upgrade --install pingmailer ./helm \
  --namespace <namespace> \
  -f my-values.yaml
```

### The four constraints

**1. Route instead of Ingress.** There is typically no default Ingress
controller, so the api-server must publish a Route:

```yaml
api-server:
  ingress:
    enabled: false
  route:
    enabled: true
    host: ""                 # OpenShift generates <name>-<ns>.apps.<cluster>
    tls:
      termination: edge      # router terminates TLS, plain HTTP to the pod
      insecureEdgeTerminationPolicy: Redirect
```

**2. `restricted-v2` assigns the UID — never pin one.** The namespace only
permits UIDs from its own allocated range. A chart that pins `runAsUser` is
rejected at *ReplicaSet* level, so you get **no pod at all** and nothing useful
from `get events` for a pod that never existed. Look at the ReplicaSet:

```bash
oc -n <namespace> describe rs -l app.kubernetes.io/name=raven-sasl-server
# Error creating: ... is forbidden: unable to validate against any security
# context constraint: ... runAsUser: Invalid value: 1001: must be in the
# ranges: [<range assigned to your namespace>]
```

`raven-sasl-server` is the one subchart that pins `1001` by default (its image
declares `ravenuser`). Clear it — and note that **`podSecurityContext: {}` does
not work**: Helm coalesces an empty map into the subchart's populated map, so
the `1001`s survive. Each key must be nulled individually:

```yaml
raven-sasl-server:
  podSecurityContext:
    runAsNonRoot: true
    runAsUser: null
    runAsGroup: null
    fsGroup: null
```

Confirm before installing — the rendered pod `securityContext` should carry no
UID:

```bash
helm template pingmailer ./helm -f my-values.yaml \
  | awk '/name: raven-sasl$/,0' | grep -A6 'securityContext:'
```

The other three subcharts already leave the UID unset and need no override.

**3. The tenant quota rejects containers without resources.** Every container
needs CPU *and* memory requests *and* limits. This includes throwaway debug
pods, which is easy to forget:

```bash
# fails: must specify limits.cpu, limits.memory, requests.cpu, requests.memory
oc -n <namespace> run probe --image=curlimages/curl --restart=Never -- curl -s http://api-server:8000/healthcheck

# works
oc -n <namespace> run probe --restart=Never --image=curlimages/curl \
  --overrides='{"spec":{"containers":[{"name":"probe","image":"curlimages/curl",
    "command":["curl","-s","http://api-server:8000/healthcheck"],
    "resources":{"requests":{"cpu":"50m","memory":"64Mi"},
                 "limits":{"cpu":"200m","memory":"128Mi"}}}]}}'
```

A related trap: debug pods run as an arbitrary UID, so `apk add` fails with
`ERROR: Unable to open log: Permission denied`. Pick an image that already has
what you need instead of installing at runtime.

**4. SMTP needs a NodePort — a Route cannot carry it.** Routes handle
HTTP/HTTPS/TLS-SNI on 80/443 only, and submission starts in plaintext before
STARTTLS, so there is no SNI to route on:

```yaml
smtp-server:
  service:
    type: NodePort
    smtpPort: 25             # what callers use
    submissionPort: 587
    nodePorts:
      smtp: 30025            # what the node actually listens on
      submission: 30587
    externalTrafficPolicy: Local   # preserve the real client IP
```

Ask the platform team to NAT `587 -> 30587` for external senders.

**Bonus trap: the api-server needs a `hostAlias` to reach SMTP.** Callers pass
`smtp_host` in the `/notify` body and the api-server verifies the SMTP TLS
certificate against that name. The Service name `smtp-server` is not on the
cert, and the public `mail.<domain>` is unreachable from inside the cluster, so
map the cert-matching name to the SMTP ClusterIP:

```yaml
api-server:
  hostAliases:
    - ip: <smtp-server ClusterIP>
      hostnames: [mail.example.com]
```

Callers then use `smtp_host: mail.example.com`. Without this, every send fails
while `/notify` still returns 202. Re-read the IP if the Service is recreated:

```bash
oc -n <namespace> get svc smtp-server -o jsonpath='{.spec.clusterIP}'
```

### Verify on OpenShift

```bash
oc -n <namespace> get pods,svc,route,pvc -l app.kubernetes.io/instance=pingmailer
HOST=$(oc -n <namespace> get route api-server -o jsonpath='{.spec.host}')
curl -sk -o /dev/null -w 'HTTP %{http_code}\n' https://$HOST/healthcheck
```

Postfix logs should show raven answering the SASL handshake:

```bash
oc -n <namespace> logs deploy/raven-sasl --tail=20
# SASL sent: MECH  OAUTHBEARER  plaintext
# SASL sent: MECH  XOAUTH2      plaintext
```

### Image gotchas

Tags get re-pushed, and not every tag is multi-arch. Check before pinning —
observed on the api-server repository:

- `latest` — amd64, serves plain HTTP, correct for an edge-terminated Route.
- `0.1.0` — exits with `ERROR: HTTPS is required. Set CERT_FILE and KEY_FILE.`
  The chart mounts no cert volume and hardcodes `scheme: HTTP` on both probes,
  so this tag needs chart changes plus a `reencrypt` Route.
- `0.1.1` — arm64 only; the pull fails with
  `no image found in image index for architecture "amd64"`.

Leaving `image.tag: ""` resolves to the chart's `appVersion`, which may not be
the tag you want. Set it explicitly, or pin a digest.

## Testing mail delivery in-cluster

The end-to-end path is: obtain an OAuth token from Thunder, then authenticate to
Postfix submission with XOAUTH2 as an address the client is authorized to send
as.

### 1. Get a token

```bash
TOKEN=$(curl -sk -X POST https://<thunder-host>/oauth2/token \
  -u "<client-id>:<client-secret>" \
  -d grant_type=client_credentials | jq -r .access_token)
```

Thunder rejects credentials sent in the POST body (`unauthorized_client: Client
is not allowed to use the specified authentication method`) — they must go in
the HTTP Basic header, i.e. `curl -u`. Decode the token and check `aud` matches
`raven-sasl-server.config.oauth.audience` and `iss` matches
`config.oauth.issuerUrl`.

### 2. Connect using a hostname the certificate covers

The TLS Secret is issued for your mail domain and its wildcard, so connecting to
the Kubernetes Service name `smtp-server` fails verification:

```
tls: failed to verify certificate: x509: certificate is valid for
*.example.com, example.com, not smtp-server
```

Connecting to the public `mail.<domain>` from inside the cluster can fail too —
a cluster generally cannot hairpin out to its own public IP
(`dial tcp <public-ip>:587: i/o timeout`). So map the cert-matching name to the
ClusterIP with a `hostAlias`:

```bash
SMTP_IP=$(oc -n <namespace> get svc smtp-server -o jsonpath='{.spec.clusterIP}')
```

```yaml
spec:
  hostAliases:
    - ip: <SMTP_IP>
      hostnames: [mail.example.com]
```

### 3. Send

Use a `python:3.12-alpine` pod — stdlib `smtplib` needs no package install,
which matters because `apk` cannot write under the assigned UID:

```python
import smtplib, ssl, base64, os
from email.message import EmailMessage
tok, user, to = os.environ["TOK"], "contact@example.com", "you@elsewhere.test"
m = EmailMessage(); m["From"], m["To"] = user, to
m["Subject"] = "Pingmailer smoke test"
m.set_content("test")
s = smtplib.SMTP("mail.example.com", 587, timeout=40)
s.ehlo(); s.starttls(context=ssl.create_default_context()); s.ehlo()
xo = base64.b64encode(f"user={user}\x01auth=Bearer {tok}\x01\x01".encode()).decode()
print(s.docmd("AUTH", "XOAUTH2 " + xo))   # expect (235, b'2.7.0 Authentication successful')
s.send_message(m); s.quit()
```

Remember the pod needs `resources` and the `hostAliases` from step 2.

### 3b. Or send through the api-server

This exercises the whole chain the way real callers do. It requires
`api-server.hostAliases` to be set (see the OpenShift section above):

```bash
curl -sk -X POST https://$HOST/notify \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"smtp_host":"mail.example.com","smtp_port":587,
       "smtp_username":"contact@example.com","smtp_sender":"contact@example.com",
       "recipient_name":"Test","recipient_email":"you@elsewhere.test",
       "app_name":"smoke test"}'
```

### 4. Confirm it actually left

A `250 ... queued as <id>` only means Postfix accepted it. Follow the queue ID
to a terminal status:

```bash
oc -n <namespace> logs deploy/smtp-server -c smtp --tail=200 | grep -E '<queue-id>|status='
# <id>: client=..., sasl_method=XOAUTH2, sasl_username=contact@example.com
# <id>: to=<...>, relay=...:25, dsn=2.0.0, status=sent (250 2.0.0 OK ...)
oc -n <namespace> exec deploy/smtp-server -c smtp -- postqueue -p   # "Mail queue is empty"
```

A `452 ... first encounter` from the receiving MX on the first attempt is normal
greylisting — Postfix retries and the retry succeeds.

Note that the api-server's `POST /notify` returns **`202 Email queued
successfully` even when the SMTP send subsequently fails**. Never treat that 202
as proof of delivery; check the api-server log for the real outcome:

```bash
oc -n <namespace> logs deploy/api-server --tail=50 | grep -i "failed to send"
```

OpenDKIM logs signing to syslog inside its own container, so per-message
signature lines do **not** appear in `oc logs deploy/opendkim-server`. Absence of
a `milter-reject` in the Postfix log means the milter accepted the message; to
actually confirm a signature, inspect the `DKIM-Signature` header on a received
message.

## Installing a subset

Every subchart has an `enabled` flag, so you can roll out incrementally:

```bash
# infrastructure first
helm upgrade --install pingmailer ./helm -n <namespace> -f my-values.yaml \
  --set smtp-server.enabled=false --set api-server.enabled=false

# then the rest
helm upgrade --install pingmailer ./helm -n <namespace> -f my-values.yaml
```

A subchart can also be installed entirely on its own — it keeps its own
`values.yaml` and README:

```bash
helm upgrade --install smtp-server ./helm/charts/smtp-server \
  -n <namespace> -f my-smtp-values.yaml
```

Note the flattening: standalone, the keys are top-level (`domain: example.com`);
under the umbrella they are nested (`smtp-server.domain`). Each subchart's own
`values.yaml` documents every option in full — this README only covers the ones
you must set.

## Exposing SMTP outside the cluster

An Ingress or an OpenShift Route **cannot** carry SMTP. They route HTTP/HTTPS
and TLS-SNI on 80/443 only, and submission (587) starts in plaintext and
upgrades via STARTTLS, so there is no SNI to route on. Pick one:

| `smtp-server.service.type` | Behaviour |
|---|---|
| `ClusterIP` (default) | in-cluster only; safe to install anywhere |
| `LoadBalancer` | real `:25` / `:587` on an external IP; needs a cloud L4 LB or MetalLB, otherwise stays `<pending>` |
| `NodePort` | high ports (30000–32767) on every node IP; pin them with `service.nodePorts` and ask the platform team to NAT 587 → the nodePort |

For `LoadBalancer` / `NodePort`, also set
`smtp-server.service.externalTrafficPolicy: Local` so Postfix sees the real
client IP — otherwise the per-client rate limits and SASL logs all see a single
SNAT address.

The api-server is different: it is plain HTTP and is meant to sit behind the
Ingress or Route, which terminates TLS for it.

## Upgrading and rolling back

```bash
helm upgrade pingmailer ./helm -n <namespace> -f my-values.yaml
helm history pingmailer -n <namespace>
helm rollback pingmailer <revision> -n <namespace>
```

Scaling constraints: `opendkim-server` and `smtp-server` must stay at
`replicaCount: 1` — both write to a single RWO PVC (the DKIM keystore and the
Postfix queue). Only `api-server` is stateless and safe to scale.

## Uninstalling

```bash
helm uninstall pingmailer -n <namespace>
```

PVCs are **not** removed by `helm uninstall`. That is deliberate — deleting
them destroys your DKIM private keys (every previously signed message stops
verifying, and you must republish a new DNS record) and any mail still sitting
in the Postfix queue. Back both up before removing them:

```bash
kubectl -n <namespace> get pvc opendkim-server-keys smtp-server-spool
```

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `Error: ... domain is required` at install | a required value is unset — see the table in step 1 |
| Postfix logs `milter-reject 4.7.1` | opendkim can't read its key. Confirm `opendkim-server` is Running and `opendkim.requireSafeKeys: "no"` is still set (needed because the PVC is group-writable). |
| SASL auth fails on 587 | `raven-sasl` pod down, or the sender's address is missing from `oauthEmailAuthorization` for that client ID |
| Pod stuck `CreateContainerConfigError` | the TLS Secret named in `tlsSecret.name` doesn't exist in the namespace yet |
| PVC stuck `Pending` | no default StorageClass — set `persistence.storageClass` explicitly |
| Pod rejected by the quota | a container lacks CPU/memory requests+limits; every `resources:` block in your values file needs both |
| Recipients mark mail as spam | DKIM/SPF/DMARC not published or not propagated — recheck step 5 |
