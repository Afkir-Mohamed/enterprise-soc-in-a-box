#!/bin/bash
# ─────────────────────────────────────────────────────────────────
# Simulator Setup Script
# Run this once to create the namespace, AWS credentials secret,
# and ConfigMaps for both simulators.
#
# Usage: bash simulators/setup.sh
# Prerequisites: kubectl configured, AWS credentials ready
# ─────────────────────────────────────────────────────────────────
set -e

echo "=== SOC-in-a-Box Simulator Setup ==="

# 1. Create namespace
kubectl create namespace soc-simulators --dry-run=client -o yaml | kubectl apply -f -
echo "✓ Namespace: soc-simulators"

# 2. Create AWS credentials secret
# Enter your AWS access key and secret when prompted
read -p "AWS Access Key ID: " AWS_KEY
read -s -p "AWS Secret Access Key: " AWS_SECRET
echo

kubectl create secret generic aws-credentials \
  --namespace soc-simulators \
  --from-literal=access_key_id="$AWS_KEY" \
  --from-literal=secret_access_key="$AWS_SECRET" \
  --dry-run=client -o yaml | kubectl apply -f -
echo "✓ Secret: aws-credentials"

# 3. Create ConfigMaps with the Python scripts
kubectl create configmap traffic-generator-script \
  --namespace soc-simulators \
  --from-file=simulate_traffic.py=simulators/traffic-generator/simulate_traffic.py \
  --dry-run=client -o yaml | kubectl apply -f -
echo "✓ ConfigMap: traffic-generator-script"

kubectl create configmap threat-simulator-script \
  --namespace soc-simulators \
  --from-file=simulate_threats.py=simulators/threat-simulator/simulate_threats.py \
  --dry-run=client -o yaml | kubectl apply -f -
echo "✓ ConfigMap: threat-simulator-script"

# 4. Deploy traffic generator CronJob
kubectl apply -f simulators/traffic-generator/cronjob.yaml -n soc-simulators
echo "✓ CronJob: traffic-generator (runs every 30 min)"

echo ""
echo "=== Setup complete ==="
echo ""
echo "To run the threat simulator now:"
echo "  kubectl apply -f simulators/threat-simulator/job.yaml -n soc-simulators"
echo "  kubectl logs -f job/threat-simulator -n soc-simulators"
echo ""
echo "To run a specific scenario:"
echo "  kubectl delete job threat-simulator -n soc-simulators 2>/dev/null; true"
echo "  SCENARIO=mass-iam envsubst < simulators/threat-simulator/job.yaml | kubectl apply -n soc-simulators -f -"
echo ""
echo "Wait 10-15 min after simulation, then check Grafana dashboard for the spike."
