# VENDORED — do not edit

This directory is a verbatim copy of the upstream Thunder Helm chart at the
[`v0.32.0`](https://github.com/thunder-id/thunderid/tree/v0.32.0/install/helm)
git tag, copyright © WSO2 LLC. Distributed under the **Apache License,
Version 2.0** — see [http://www.apache.org/licenses/LICENSE-2.0](http://www.apache.org/licenses/LICENSE-2.0).
The per-file copyright headers are preserved unchanged.

It is the **library** that the silver-thunder umbrella wraps.

- **Configuration overrides go in the umbrella, not here.** Edit
  [`../../values.yaml`](../../values.yaml) (or a private overlay passed
  with `-f`). All keys you set under the `thunder:` block in the
  umbrella's values lay over `./values.yaml` at template-render time.
- **Updating this directory:** see the "Updating the vendored subchart"
  section of [`../../README.md`](../../README.md) — it's a single
  `curl … | tar -xz` + `cp -R` recipe.
- **Provenance:** the upstream README (62 KB) and `.helmignore` were
  intentionally removed during vendoring because they aren't needed at
  install time and only added noise. Everything else is bit-identical to
  the upstream tag.
