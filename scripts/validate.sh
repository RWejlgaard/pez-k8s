#!/usr/bin/env bash

# Validate every manifest and kustomize overlay in this repo against its JSON
# schema, mirroring what Flux's kustomize-controller does before it applies.
#
# Three passes:
#   1. kubeconform the loose Flux Kustomization/GitRepository CRs under
#      ./clusters/<cluster>/ that are applied by `flux bootstrap`, not built by
#      kustomize.
#   2. `kustomize build` every directory that owns a kustomization.yaml and pipe
#      the rendered output through kubeconform.
#
# Schemas: the Kubernetes defaults, the Flux CRD schemas (downloaded below), and
# the community CRDs-catalog for everything else (Istio, Gateway API, Karpenter,
# kro). Anything still unknown is skipped via -ignore-missing-schemas rather
# than failing the build.
#
# Requires: kustomize, kubeconform, curl, tar.

set -o errexit
set -o pipefail

# mirror kustomize-controller build options
kustomize_flags=("--load-restrictor=LoadRestrictionsNone")
kustomize_config="kustomization.yaml"

# Skip Secrets: they're applied out-of-band (Proxmox creds, k3s join token) and
# never live in git, so there's nothing here to validate.
kubeconform_flags=(
  "-strict"
  "-ignore-missing-schemas"
  "-skip=Secret"
  "-schema-location" "default"
  "-schema-location" "/tmp/flux-crd-schemas/master-standalone-strict"
  "-schema-location" "https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"
  "-verbose"
)

echo "INFO - Downloading Flux OpenAPI schemas"
mkdir -p /tmp/flux-crd-schemas/master-standalone-strict
curl -fsSL https://github.com/fluxcd/flux2/releases/latest/download/crd-schemas.tar.gz | \
  tar zxf - -C /tmp/flux-crd-schemas/master-standalone-strict

echo "INFO - Validating cluster Flux resources"
find ./clusters -maxdepth 2 -type f -name '*.yaml' -print0 | while IFS= read -r -d $'\0' file; do
  echo "INFO - Validating ${file}"
  kubeconform "${kubeconform_flags[@]}" "${file}"
done

echo "INFO - Validating kustomizations"
find . -type f -name "${kustomize_config}" -print0 | while IFS= read -r -d $'\0' file; do
  dir="${file%${kustomize_config}}"
  echo "INFO - Validating kustomization ${dir}"
  kustomize build "${dir}" "${kustomize_flags[@]}" | kubeconform "${kubeconform_flags[@]}"
done

echo "INFO - All manifests valid"
