# silver-raven-sasl Helm chart

Helm chart for the `raven-sasl` service (`ghcr.io/lsflk/raven-sasl`) — the
Kubernetes counterpart of the `raven-sasl-server` block in this repo's
[docker-compose.yml](../../../docker-compose.yml).

Raven is a Dovecot-compatible SASL authentication daemon that Postfix
(`smtpd_sasl_path = inet:raven-sasl:12345`) consults during SMTP submission.
It validates two flavours of credentials:

- **PLAIN / LOGIN** — forwarded to Thunder's
  `/auth/credentials/authenticate` endpoint.
- **OAUTHBEARER** (RFC 7628) — JWT validated against Thunder's JWKS, then
  the sender address is checked against an OAuth `client_id → emails`
  allowlist.

## What this chart deploys

- A `ConfigMap` containing both `raven.yaml` (rendered from your values) and
  `oauth_client_email_authorization.json` (the OAuth allowlist).
- A `Deployment` running `raven-sasl` as the unprivileged `ravenuser`
  (UID/GID **1001**), with `cap_drop: [ALL]` and
  `allowPrivilegeEscalation: false` — mirroring the hardening you'd expect
  from the docker-compose service.
- A `ClusterIP Service` on port 12345 named `raven-sasl` (configurable)
  so the existing Postfix `master.cf` (`inet:raven-sasl:12345`) works unmodified.
- Optionally mounts a cert-manager-managed `Secret` at `/certs`
  (compatible with the [silver-certificates chart](../certbot-server/) —
  `<dash-domain>-tls` Secrets with `tls.crt`/`tls.key` keys get
  remapped to `fullchain.pem`/`privkey.pem` automatically).

What this chart does **not** do (vs. docker-compose):

- The `docker.sock` mount in docker-compose is **not** carried over — the
  raven-sasl binary doesn't use it (confirmed by inspecting the image
  entrypoint: `exec ./raven-sasl -tcp :12345 -config /etc/raven/raven.yaml`).
- `DB_FILE` env var is dropped — also unused by this binary.
- The `/etc/raven` mount is `:ro` here (the binary only reads its config).

## Install

Sensitive values are intentionally empty in `values.yaml`. Put them in a
file you do **not** commit:

```yaml
# my-raven-values.yaml
config:
  domain: mail.example.com
  oauth:
    audience:
      - your-mail-app-client-id

oauthEmailAuthorization:
  your-mail-app-client-id:
    - alerts@example.com
    - noreply@example.com

# Optional — TLS Secret produced by the silver-certificates chart
tlsSecret:
  name: mail-example-com-tls
```

```bash
helm upgrade --install raven-sasl ./helm/charts/raven-sasl-server \
  --namespace pingmailer --create-namespace \
  -f my-raven-values.yaml
```

The chart `fail`s with a clear message if `config.domain`,
`config.oauth.audience`, or `oauthEmailAuthorization` is missing.

## Values

| Key                                | Default                                                                    | Notes                                              |
|------------------------------------|----------------------------------------------------------------------------|----------------------------------------------------|
| `config.domain`                    | `""` (**required**)                                                        | Primary mail domain                                |
| `config.authServerUrl`             | `https://thunder-server:8090/auth/credentials/authenticate`                | Override for cross-namespace Thunder               |
| `config.saslScope`                 | `tcp_only`                                                                 |                                                    |
| `config.oauth.issuerUrl`           | `""` → derived as `https://<domain>:8090`                                  |                                                    |
| `config.oauth.jwksUrl`             | `""` → derived as `https://<domain>:8090/oauth2/jwks`                      |                                                    |
| `config.oauth.audience`            | `[]` (**required**)                                                        | OAuth client IDs Raven will accept                 |
| `config.oauth.clockSkewSeconds`    | `60`                                                                       |                                                    |
| `oauthEmailAuthorization`          | `{}` (**required**)                                                        | `client_id → [authorized senders]`                 |
| `tlsSecret.name`                   | `""`                                                                       | When empty, no `/certs` mount is created           |
| `tlsSecret.alreadyRenamed`         | `false`                                                                    | Set to `true` if the Secret already uses fullchain.pem / privkey.pem keys |
| `service.port`                     | `12345`                                                                    |                                                    |
| `replicaCount`                     | `1`                                                                        | Raven is stateless; you can scale, but Postfix talks to one Service IP anyway |
| `fullnameOverride`                 | `raven-sasl`                                                               | Keeps the Service DNS short for Postfix           |
| `podSecurityContext.runAsUser`     | `1001`                                                                     | `ravenuser` UID baked into the image              |

## Wiring with the rest of the stack

```
                         ┌──────────────────────┐
                         │  Postfix (smtp)      │
                         │  smtpd_sasl_path =   │
                         │   inet:raven-sasl    │
                         │        :12345        │
                         └──────────┬───────────┘
                                    │ Dovecot SASL
                                    ▼
                         ┌──────────────────────┐
                         │  raven-sasl :12345   │  <- this chart
                         └──────┬─────────┬─────┘
              auth_server_url │         │ oauth_jwks_url
                              ▼         ▼
                         ┌──────────────────────┐
                         │  Thunder :8090       │
                         │  /auth/credentials   │
                         │  /oauth2/jwks        │
                         └──────────────────────┘
```

The chart assumes `thunder-server` resolves in cluster DNS. Override
`config.authServerUrl` / `config.oauth.issuerUrl` / `config.oauth.jwksUrl`
when Thunder is in a different namespace or behind an ingress.

## Uninstall

```bash
helm uninstall raven-sasl -n pingmailer
```

Nothing persistent is created by this chart — uninstall is clean.
