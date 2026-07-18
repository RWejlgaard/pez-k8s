#!/usr/bin/env bash

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
