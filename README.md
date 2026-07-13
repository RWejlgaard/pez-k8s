# pez-k8s

Multi-cluster GitOps repository (repo name predates the second cluster — kept
as-is). Currently hosts config for two independent k3s-on-Proxmox clusters,
each scaled out by Karpenter and each reconciled by its own
[ArgoCD](https://argo-cd.readthedocs.io) instance:

| Cluster | Proxmox host | UI | Ingress hostnames |
|---------|--------------|----|--------------------|
| pez-london | london-a.pez.sh | `https://argocd.lon.pez.sh` | `*.lon.pez.sh` |
| pez-copenhagen | copenhagen-a.pez.sh | `https://argocd.cph.pez.sh` | `*.cph.pez.sh` |

## Layout

Everything is shared in a `base/`, and each cluster is a small kustomize
overlay holding only what genuinely differs there (hostnames, the Tailscale
ingress IP, Karpenter region and fleet ceiling):

```
clusters/
  base/
    argocd/              # ArgoCD install + UI HTTPRoute (placeholder hostname)
    applications/        # root.yaml (self-managing "app of apps"),
                         # infrastructure.yaml, apps.yaml (placeholder paths)
  pez-london/
    argocd/kustomization.yaml   # base/argocd + UI hostname patch
    kustomization.yaml          # argocd/ + base/applications + path patches
  pez-copenhagen/               # same two files
infrastructure/
  istio/                 # shared ambient-mesh base
  clusters/
    base/                # ingress gateway, shared Gateway, karpenter/
    pez-london/kustomization.yaml     # IP, hostname, region, fleet-ceiling patches
    pez-copenhagen/kustomization.yaml
```

Each cluster's `root` Application syncs `clusters/<cluster>/` (one kustomize
source), which renders the ArgoCD install plus the three bootstrap
Applications with their paths patched to that cluster.

Workloads live in a separate repo:
[`pez-k8s-apps`](https://github.com/RWejlgaard/pez-k8s-apps), wired to each
cluster via the `apps` Application.

## Bootstrap (one-time, on a fresh cluster)

ArgoCD self-manages its own install once bootstrapped, but getting there requires applying
the first manifests before ArgoCD exists to reconcile them. Run against the target cluster's
kubecontext, substituting `pez-london` or `pez-copenhagen`:

```sh
kubectl apply -k clusters/<cluster>/argocd   # installs ArgoCD, --insecure mode, the UI route
kubectl apply -k clusters/<cluster>          # adds the bootstrap Applications; ArgoCD takes over
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
| istio-ingressgateway | Pinned to `k8s-control-plane`, exposed on that cluster's Tailscale IP via `service.externalIPs` (TLS at Caddy). Labeled `istio.io/gateway-name: shared-gateway` to bind to the shared Gateway in manual-deployment mode. Base: `infrastructure/clusters/base/ingressgateway.yaml`; IP patched per cluster |
| shared-gateway | Gateway API `Gateway` (port 8080) that apps attach to via `HTTPRoute`; replaces per-app Istio `Gateway`/`VirtualService`. Base: `infrastructure/clusters/base/shared-gateway.yaml`; wildcard hostname patched per cluster |
| Karpenter config | `infrastructure/clusters/base/karpenter/`: `NodePool`/`ProxmoxNodeClass`/`ProxmoxTemplate` + the non-sensitive cloud-init `karpenter-template` Secret. Region and fleet ceiling patched per cluster. The controller + CRDs are still Helm-managed out-of-band (see below) |
| Sealed Secrets | Bitnami controller, shared across clusters via `infrastructure/sealed-secrets/`. Deployed as `sealed-secrets-controller` in `kube-system` (matches `kubeseal`'s zero-flag defaults). **Both clusters share one keypair** (pez-copenhagen was seeded with pez-london's key, its own auto-generated key deleted) — a `SealedSecret` sealed against either cluster decrypts on both. This trades per-cluster isolation for being able to commit one `SealedSecret` that deploys unmodified everywhere; see "Sealing a secret" below |
| Kubernetes Monitoring | Grafana's `k8s-monitoring` Alloy chart (`infrastructure/clusters/base/k8s-monitoring.yaml`, `cluster.name` patched per cluster; currently unwired, see the base kustomization) in the `monitoring` namespace. Ships cluster/host metrics, cluster events, node + pod logs, and an OTLP receiver for app traces/metrics/logs, all through a single Grafana Cloud OTLP Gateway destination. Credentials: `grafana-cloud-credentials` `SealedSecret` shared across clusters, `infrastructure/grafana-cloud/` |

Each Istio Helm component (`infrastructure/istio/{base,istiod,cni,ztunnel}.yaml` +
per-cluster `ingressgateway.yaml`) is its own ArgoCD `Application` with a
`argocd.argoproj.io/sync-wave` annotation encoding the install order (base ->
istiod -> cni -> ztunnel -> ingressgateway) that used to be Flux's `dependsOn`.

### Sealing a secret

Both clusters share a keypair, so sealing against either context produces a
`SealedSecret` that decrypts on both:

```sh
kubectl create secret generic <name> -n <namespace> --dry-run=client -o yaml \
    --from-literal=key=value \
  | kubeseal --context pez-london -o yaml > sealedsecret.yaml
```

(Or fetch the cert once and seal offline: `kubeseal --context pez-london
--fetch-cert > cert.pem`, then `kubeseal --cert cert.pem -o yaml`.)

Commit the resulting `SealedSecret`. See `pez-k8s-apps/README.md` for where
a workload's `SealedSecret` manifest goes.

**Back up the shared controller private key somewhere outside git** —
losing it means losing the ability to decrypt every `SealedSecret` on both
clusters, since there's now only one copy of this key in existence
(pez-copenhagen's original auto-generated key was deleted when it was
seeded with pez-london's):

```sh
kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key \
  --context pez-london -o yaml > sealed-secrets-key-backup.yaml
```

Store that file somewhere durable and *not* in this git repo (a password
manager or an encrypted archive), then delete the local copy.

## Adding a cluster

Copy an existing cluster overlay pair and change the values in the patches:

1. `clusters/<new-cluster>/` (two kustomizations: ArgoCD UI hostname patch +
   the three Application path patches)
2. `infrastructure/clusters/<new-cluster>/kustomization.yaml` (Tailscale IP,
   wildcard hostname, Karpenter region, fleet ceiling)
3. `clusters/<new-cluster>/` in the `pez-k8s-apps` repo (see its README)
4. Out-of-band: install the Karpenter controller via Helm, apply the two
   Karpenter secrets, seed the sealed-secrets keypair (see below), then run
   the bootstrap commands above.

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
