# k3s Lab Setup

This project's AWS side (Terraform in `terraform/`) doesn't need this at all —
it's only needed once we get to **Phase 2** (Grafana) and **Phase 4** (simulators).
Setting it up now means it's ready when we get there.

## 1. Install k3s

On the machine you want to be your cluster's control-plane node (a spare mini-PC,
an old laptop, a VM — anything with a couple GB of RAM is plenty for this lab):

```bash
curl -sfL https://get.k3s.io | sh -
```

This installs a single-node k3s cluster (control plane + worker on the same box)
and starts it as a systemd service. Check it's running:

```bash
sudo k3s kubectl get nodes
```

## 2. Get a kubeconfig you can use from your normal user / laptop

```bash
sudo cat /etc/rancher/k3s/k3s.yaml
```

Copy that to `~/.kube/config` on the machine you'll run `kubectl`/`helm` from
(or merge it into an existing kubeconfig). If you're working from a different
machine than the k3s node itself, replace `127.0.0.1` in the `server:` line
with the k3s node's actual IP address.

```bash
mkdir -p ~/.kube
sudo cat /etc/rancher/k3s/k3s.yaml | sed "s/127.0.0.1/<k3s-node-ip>/" > ~/.kube/config
chmod 600 ~/.kube/config
kubectl get nodes   # should show your node as Ready
```

## 3. Install Helm (if you don't have it)

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version
```

## 4. Confirm outbound internet access

The Grafana pod needs to reach the AWS Athena API over the internet (no VPN
required — see ARCHITECTURE.md for why). From the k3s node:

```bash
curl -s -o /dev/null -w "%{http_code}\n" https://athena.eu-west-1.amazonaws.com
```

Any HTTP response code (even 403) confirms outbound connectivity is fine —
we're not authenticating yet, just checking the network path.

## What's next

Nothing to deploy yet — Grafana itself gets installed in Phase 2 once the
Athena data source is ready to point at. This doc just gets the cluster
itself ready ahead of time.
