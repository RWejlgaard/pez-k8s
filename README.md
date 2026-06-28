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
| Gateway API CRDs | Standard channel, pinned in `infrastructure/kustomization.yaml`; required by the `istio` GatewayClass and `shared-gateway` |
| Istio base / istiod / cni / ztunnel | Ambient mesh (`profile: ambient`), `global.platform: k3s` for CNI paths |
| istio-ingressgateway | Pinned to `k8s-control-plane`, exposed on the Tailscale IP via `service.externalIPs` (TLS at Caddy). Labeled `istio.io/gateway-name: shared-gateway` to bind to the shared Gateway in manual-deployment mode |
| shared-gateway | Gateway API `Gateway` (`*.k8s.pez.sh`, port 8080) that apps attach to via `HTTPRoute`; replaces per-app Istio `Gateway`/`VirtualService` |
| Karpenter config | `infrastructure/karpenter.yaml` — `NodePool`/`ProxmoxNodeClass`/`ProxmoxTemplate` + the non-sensitive cloud-init `karpenter-template` Secret. The controller + CRDs are still Helm-managed out-of-band (see below) |

## Managed outside Flux (for now)

- **Karpenter controller** — the `karpenter-provider-proxmox` controller and its
  CRDs are still installed via Helm (chart 0.4.7 / app v0.11.0) directly on the
  cluster; the declarative node-fleet config it consumes now lives in
  `infrastructure/karpenter.yaml`. Folding the controller itself into a Flux
  `HelmRelease` is the remaining step.
- **Secrets** — the Proxmox API credentials (`karpenter-provider-proxmox`) and
  the k3s join token (`karpenter-template-values`, referenced by the
  `ProxmoxNodeClass` `metadataOptions`) are applied directly to the cluster and
  intentionally kept out of git.
