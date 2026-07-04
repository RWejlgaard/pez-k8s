# pez-k8s

Top-level GitOps repository for the **pez-k8s** cluster (single-node k3s on
Proxmox, scaled out by Karpenter). Reconciled by [ArgoCD](https://argo-cd.readthedocs.io),
UI at `https://argocd.k8s.pez.sh`.

## Layout

```
clusters/pez-k8s/
  argocd/              # ArgoCD install (pinned upstream manifest) + insecure-mode
                        # patch + HTTPRoute for argocd.k8s.pez.sh
  root.yaml            # Self-managing "app of apps" Application (bootstrap)
  infrastructure.yaml  # ArgoCD Application -> ./infrastructure
  apps.yaml            # ArgoCD Application -> pez-k8s-apps repo (sync-wave after infrastructure)
infrastructure/         # system components (Istio, ambient mesh + ingress gateway)
```

Workloads live in a separate repo:
[`pez-k8s-apps`](https://github.com/RWejlgaard/pez-k8s-apps).

## Bootstrap (one-time, on a fresh cluster)

ArgoCD self-manages its own install once bootstrapped, but getting there requires applying
the first manifests before ArgoCD exists to reconcile them:

```sh
kubectl apply -k clusters/pez-k8s/argocd   # installs ArgoCD, --insecure mode, the UI route
kubectl apply -f clusters/pez-k8s/root.yaml  # ArgoCD takes over from here
```

Fetch the initial admin password (rotate it after logging in):

```sh
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

## Infrastructure

| Component | Notes |
|-----------|-------|
| Gateway API CRDs | Standard channel, pinned in `infrastructure/kustomization.yaml`; required by the `istio` GatewayClass and `shared-gateway` |
| Istio base / istiod / cni / ztunnel | Ambient mesh (`profile: ambient`), `global.platform: k3s` for CNI paths |
| istio-ingressgateway | Pinned to `k8s-control-plane`, exposed on the Tailscale IP via `service.externalIPs` (TLS at Caddy). Labeled `istio.io/gateway-name: shared-gateway` to bind to the shared Gateway in manual-deployment mode |
| shared-gateway | Gateway API `Gateway` (`*.k8s.pez.sh`, port 8080) that apps attach to via `HTTPRoute`; replaces per-app Istio `Gateway`/`VirtualService` |
| Karpenter config | `infrastructure/karpenter.yaml` — `NodePool`/`ProxmoxNodeClass`/`ProxmoxTemplate` + the non-sensitive cloud-init `karpenter-template` Secret. The controller + CRDs are still Helm-managed out-of-band (see below) |
| kro | `infrastructure/kro/` — the [kro](https://kro.run) controller (ArgoCD `Application` against the OCI chart) plus the `workload` `ResourceGraphDefinition`. Defines the `Workload` CRD that `pez-k8s-apps` uses to describe an app in one manifest; kro reconciles each into a namespace + Deployment/Service/PDB/HPA/HTTPRoute/AuthorizationPolicy. Pods run hardened by default (non-root uid 65532, all capabilities dropped, read-only rootfs, no SA token) with `allowRoot`/`writableRootFilesystem` escape hatches; `maxReplicas` enables CPU autoscaling, `public: false` skips the HTTPRoute for mesh-internal services |

Each Istio Helm component (`infrastructure/istio/{base,istiod,cni,ztunnel,ingressgateway}.yaml`)
is its own ArgoCD `Application` with a `argocd.argoproj.io/sync-wave` annotation encoding the
install order (base -> istiod -> cni -> ztunnel -> ingressgateway) that used to be Flux's
`dependsOn`.

## Managed outside ArgoCD (for now)

- **Karpenter controller** — the `karpenter-provider-proxmox` controller and its
  CRDs are still installed via Helm (chart 0.4.7 / app v0.11.0) directly on the
  cluster; the declarative node-fleet config it consumes now lives in
  `infrastructure/karpenter.yaml`. Folding the controller itself into an ArgoCD
  `Application` is the remaining step.
- **Secrets** — the Proxmox API credentials (`karpenter-provider-proxmox`) and
  the k3s join token (`karpenter-template-values`, referenced by the
  `ProxmoxNodeClass` `metadataOptions`) are applied directly to the cluster and
  intentionally kept out of git.
