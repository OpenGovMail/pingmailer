# silver-thunder Helm chart

Umbrella chart that wraps the upstream
[`thunder`](https://github.com/thunder-id/thunderid/tree/v0.32.0/install/helm)
Helm chart at **v0.32.0** and bakes this repo's bootstrap scripts into a
ConfigMap so installing Thunder on Kubernetes is the same one-step flow as
the other mail-plane charts:

```bash
helm upgrade --install thunder ./mail-infra/helm/thunder \
  --namespace pingmailer --create-namespace \
  -f my-thunder-values.yaml
```

No `helm dependency build` step — the subchart is **vendored** under
`charts/thunder/` so the umbrella chart is fully self-contained.

## Version pin

| | Value |
|---|---|
| Subchart | `thunder` v0.32.0 (vendored from [github.com/thunder-id/thunderid @ v0.32.0](https://github.com/thunder-id/thunderid/tree/v0.32.0/install/helm)) |
| Image | `ghcr.io/asgardeo/thunder:0.32.0` (the only published 0.32.0 image) |

This matches the version pinned in this repo's
[docker-compose.yml](../../../docker-compose.yml). To bump to a newer
Thunder, follow the "Updating the vendored subchart" section below.

## Directory layout

```
mail-infra/helm/thunder/
├── Chart.yaml                  ← umbrella chart metadata
├── values.yaml                 ← UMBRELLA DEFAULTS (where overrides live)
├── values.example.yaml         ← starter overlay for users
├── README.md                   ← this file
├── .helmignore
│
├── files/                      ← bundled into the bootstrap ConfigMap
│   ├── 20-default-resources.sh   (copy of mail-infra/scripts/thunder/01-...)
│   └── 30-sample-resources.sh    (copy of mail-infra/scripts/thunder/02-...)
│
├── templates/                  ← umbrella's own K8s resources
│   ├── _helpers.tpl
│   ├── NOTES.txt
│   └── bootstrap-configmap.yaml  (renders files/*.sh → "thunder-bootstrap" ConfigMap)
│
└── charts/                     ← VENDORED upstream — treat as library code
    └── thunder/                  (verbatim from thunder-id/thunderid @ v0.32.0)
        ├── Chart.yaml
        ├── values.yaml           ← upstream defaults; your overrides go in
        │                           ../../values.yaml under `thunder:`, NOT here
        ├── VENDORED.md           ← provenance + "don't edit" reminder
        ├── conf/                 ← deployment.yaml, console/gate config.js, etc.
        └── templates/            ← 15 Kubernetes resource templates
```

### Which `values.yaml` do I edit?

| File | What it is | Edit? |
|---|---|---|
| `values.yaml` (top level) | Umbrella overrides — pre-configures SQLite, persistence, image pin, bootstrap wiring. All keys under `thunder:` flow into the subchart. | **Yes** (or copy `values.example.yaml` to a private overlay) |
| `charts/thunder/values.yaml` | Vendored upstream defaults (Postgres + HPA + readOnlyRootFilesystem etc.). Library code. | **No** — overlaid by the umbrella |

## How it wires together

- The vendored `thunder` v0.32.0 subchart sits under `charts/thunder/`.
  Helm auto-discovers subcharts there; no `helm dependency build` step is
  required.
- The two `files/*.sh` are bundled into a `ConfigMap` named
  `thunder-bootstrap` by [templates/bootstrap-configmap.yaml](templates/bootstrap-configmap.yaml)
  via `(.Files.Glob "files/*.sh").AsConfig`.
- The umbrella's [values.yaml](values.yaml) sets
  `thunder.bootstrap.configMap.name: thunder-bootstrap` and
  `thunder.bootstrap.configMap.files: [20-..., 30-...]` (Pattern 2 —
  additive), so the subchart's setup job mounts our scripts alongside
  its built-in `10-*` defaults.
- The repo's scripts call `thunder_api_call`. The vendored v0.32.0
  `common.sh` defines exactly that function (the rename to
  `thunderid_api_call` happened later in 0.38.0+), so no shim is needed.

Bootstrap script ordering: chart's built-ins `10-*` → ours `20-default-resources.sh`
→ ours `30-sample-resources.sh`. The repo's script already handles 4xx
responses by falling back to GET, so overlap with the chart's defaults
is safe.

## Source-of-truth note

`mail-infra/helm/thunder/files/*.sh` is a **copy** of
`mail-infra/scripts/thunder/*.sh` because Helm's `.Files.Get` only reads
files inside the chart directory. When you change the canonical scripts,
re-sync:

```bash
cp mail-infra/scripts/thunder/01-default-resources.sh \
   mail-infra/helm/thunder/files/20-default-resources.sh
cp mail-infra/scripts/thunder/02-sample-resources.sh \
   mail-infra/helm/thunder/files/30-sample-resources.sh
```

## Install

```bash
# 1. Author your private overrides (start from values.example.yaml).
cp mail-infra/helm/thunder/values.example.yaml my-thunder-values.yaml
$EDITOR my-thunder-values.yaml      # set hostname, TLS Secret

# 2. Install.
helm upgrade --install thunder ./mail-infra/helm/thunder \
  --namespace pingmailer --create-namespace \
  -f my-thunder-values.yaml
```

## Required overrides

The chart prints a `WARNING` in NOTES.txt when these are empty after
install but does not `fail` outright — the upstream chart owns most of
the validation logic, and we avoid double error messages.

| Key | What it controls |
|---|---|
| `thunder.configuration.server.publicUrl` | Browser-visible URL Thunder advertises in OAuth metadata |
| `thunder.configuration.gateClient.hostname` | Hostname used by the Gate frontend |
| `thunder.configuration.cors.allowedOrigins` | CORS allowlist (typically `["https://<host>"]`) |
| `thunder.configuration.passkey.allowedOrigins` | WebAuthn RP origin allowlist |
| `thunder.ingress.hostname` | Ingress host |
| `thunder.ingress.tlsSecretsName` | Name of a TLS Secret (e.g. from the silver-certificates chart) |

Note: at v0.32.0 there is **no admin user setup** in the chart itself
(no `setup.admin.*` block). The repo's `20-default-resources.sh` is
responsible for creating the admin user, and reads the credentials from
the script's environment / hardcoded defaults — review the script if you
need to change them.

## Vendored subchart

The upstream chart was published only as source at the git tag
[`v0.32.0`](https://github.com/thunder-id/thunderid/tree/v0.32.0/install/helm)
(later versions moved to OCI as `thunderid` 0.38.0+). To keep the
single-command install promise, we vendor the source into
`charts/thunder/` directly. Helm 3 picks it up automatically — no
`helm dependency build` round trip needed.

### Updating the vendored subchart

To pull a newer point release while staying on 0.32.x (none currently
published) or a different tag entirely:

```bash
# Replace VERSION with the target tag
VERSION=v0.32.0
curl -sL "https://codeload.github.com/thunder-id/thunderid/tar.gz/refs/tags/${VERSION}" \
  | tar -xz -C /tmp
rm -rf mail-infra/helm/thunder/charts/thunder
cp -R "/tmp/thunderid-${VERSION#v}/install/helm" \
      mail-infra/helm/thunder/charts/thunder
```

After updating, re-check `values.yaml` against the new subchart's
`values.yaml` for schema changes (e.g. flat vs nested SQLite knobs).

## Uninstall

```bash
helm uninstall thunder -n pingmailer
```

The SQLite PVC is preserved. Delete it explicitly to wipe state:

```bash
kubectl -n pingmailer delete pvc -l app.kubernetes.io/instance=thunder
```
