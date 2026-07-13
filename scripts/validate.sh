#!/usr/bin/env bash

# Validate every manifest and kustomize overlay in this repo against its JSON
# schema, mirroring what ArgoCD's repo-server does before it applies.
#
# Single pass: `kustomize build` every directory that owns a kustomization.yaml
# (bases and cluster overlays alike) and pipe the rendered output through
# kubeconform. Every manifest in the repo, including the ArgoCD Application
# CRs, belongs to some kustomization now, nothing is applied loose.
#
# Schemas: the Kubernetes defaults and the community CRDs-catalog (Istio,
# Gateway API, Karpenter, ArgoCD's Application/AppProject). Anything still
# unknown is skipped via -ignore-missing-schemas rather than failing the build.
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
  "-schema-location" "https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"
  "-verbose"
)

echo "INFO - Validating kustomizations"
find . -type f -name "${kustomize_config}" -print0 | while IFS= read -r -d $'\0' file; do
  dir="${file%${kustomize_config}}"
  echo "INFO - Validating kustomization ${dir}"
  kustomize build "${dir}" "${kustomize_flags[@]}" | kubeconform "${kubeconform_flags[@]}"
done

echo "INFO - All manifests valid"
