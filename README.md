# pez-k8s

Multi-cluster GitOps repository (repo name predates the second cluster — kept
as-is). Currently hosts config for two independent k3s-on-Proxmox clusters,
each scaled out by Karpenter and each reconciled by its own
[ArgoCD](https://argo-cd.readthedocs.io) instance:

| Cluster | Proxmox host | UI | Ingress hostnames |
|---------|--------------|----|--------------------|
| pez-london (formerly pez-k8s) | london-a.pez.sh | `https://argocd.lon.pez.sh` | `*.lon.pez.sh` |
| pez-copenhagen | copenhagen-a.pez.sh | `https://argocd.cph.pez.sh` | `*.cph.pez.sh` |

## Layout

```
clusters/
  pez-london/
    argocd/              # ArgoCD install + HTTPRoute
    root.yaml            # Self-managing "app of apps"
    infrastructure.yaml  # -> infrastructure/clusters/pez-london
    apps.yaml             # -> pez-k8s-apps repo
  pez-copenhagen/
    argocd/
    root.yaml
    infrastructure.yaml  # -> infrastructure/clusters/pez-copenhagen
infrastructure/
  istio/                # shared ambient-mesh base
  clusters/
    pez-london/          # ingress gateway, Gateway hostname, karpenter/
    pez-copenhagen/
```

Workloads live in a separate repo:
[`pez-k8s-apps`](https://github.com/RWejlgaard/pez-k8s-apps) — currently only
wired up to pez-london via `clusters/pez-london/apps.yaml`.

## Bootstrap (one-time, on a fresh cluster)

ArgoCD self-manages its own install once bootstrapped, but getting there requires applying
the first manifests before ArgoCD exists to reconcile them. Run against the target cluster's
kubecontext, substituting `pez-london` or `pez-copenhagen`:

```sh
kubectl apply -k clusters/<cluster>/argocd   # installs ArgoCD, --insecure mode, the UI route
kubectl apply -f clusters/<cluster>/root.yaml  # ArgoCD takes over from here
```

Fetch the initial admin password (rotate it after logging in):

```sh
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

## Infrastructure

| Component | Notes |
|-----------|-------|
| Gateway API CRDs | Standard channel, pinned in `infrastructure/istio/kustomization.yaml`; required by the `istio` GatewayClass and `shared-gateway` |
| Istio base / istiod / cni / ztunnel | Ambient mesh (`profile: ambient`), `global.platform: k3s` for CNI paths. Shared across clusters via `infrastructure/istio/` |
| istio-ingressgateway | Pinned to `k8s-control-plane`, exposed on that cluster's Tailscale IP via `service.externalIPs` (TLS at Caddy). Labeled `istio.io/gateway-name: shared-gateway` to bind to the shared Gateway in manual-deployment mode. Per-cluster: `infrastructure/clusters/<cluster>/ingressgateway.yaml` |
| shared-gateway | Gateway API `Gateway` (per-cluster hostname, port 8080) that apps attach to via `HTTPRoute`; replaces per-app Istio `Gateway`/`VirtualService`. Per-cluster: `infrastructure/clusters/<cluster>/shared-gateway.yaml` |
| Karpenter config | `infrastructure/clusters/<cluster>/karpenter/` — `NodePool`/`ProxmoxNodeClass`/`ProxmoxTemplate` + the non-sensitive cloud-init `karpenter-template` Secret. The controller + CRDs are still Helm-managed out-of-band (see below) |

Each Istio Helm component (`infrastructure/istio/{base,istiod,cni,ztunnel}.yaml` +
per-cluster `ingressgateway.yaml`) is its own ArgoCD `Application` with a
`argocd.argoproj.io/sync-wave` annotation encoding the install order (base ->
istiod -> cni -> ztunnel -> ingressgateway) that used to be Flux's `dependsOn`.

## Managed outside ArgoCD (for now)

- **Karpenter controller** — the `karpenter-provider-proxmox` controller and its
  CRDs are still installed via Helm (chart 0.4.7 / app v0.11.0) directly on each
  cluster; the declarative node-fleet config it consumes lives in
  `infrastructure/clusters/<cluster>/karpenter/`. Folding the controller itself
  into an ArgoCD `Application` is the remaining step.
- **Secrets** — the Proxmox API credentials (`karpenter-provider-proxmox`) and
  the k3s join token (`karpenter-template-values`, referenced by the
  `ProxmoxNodeClass` `metadataOptions`) are applied directly to each cluster and
  intentionally kept out of git. Each cluster's Proxmox `region` (in its
  ProxmoxNodeClass and in the out-of-band secret's `config.yaml`) must match.
