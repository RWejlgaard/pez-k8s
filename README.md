# pez-k8s

Top-level GitOps repository for the **pez-k8s** cluster (single-node k3s on
Proxmox, scaled out by Karpenter). Reconciled by [Flux](https://fluxcd.io).

## Layout

```
clusters/pez-k8s/
  flux-system/        # Flux components + sync (managed by `flux bootstrap`)
  infrastructure.yaml # Flux Kustomization -> ./infrastructure
  apps.yaml           # GitRepository(pez-k8s-apps) + Flux Kustomization (depends on infrastructure)
infrastructure/       # system components (Istio, ambient mesh + ingress gateway)
```

Workloads live in a separate repo:
[`pez-k8s-apps`](https://github.com/RWejlgaard/pez-k8s-apps).

## Infrastructure

| Component | Notes |
|-----------|-------|
| Istio base / istiod / cni / ztunnel | Ambient mesh (`profile: ambient`), `global.platform: k3s` for CNI paths |
| istio-ingressgateway | Pinned to `k8s-control-plane`, exposed on the Tailscale IP via `service.externalIPs` (TLS at Caddy) |

## Managed outside Flux (for now)

- **Karpenter (Proxmox provider)** — controller + `ProxmoxTemplate`/`ProxmoxNodeClass`/`NodePool` are applied ad-hoc; to be folded into GitOps later.
- **Secrets** — the Proxmox API credentials and k3s join token are applied
  directly to the cluster and intentionally kept out of git.
