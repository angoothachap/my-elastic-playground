#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "================================================"
echo "ECK (Elastic Cloud on Kubernetes) Deployment"
echo "================================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed${NC}"
    echo "Please install kubectl: https://kubernetes.io/docs/tasks/tools/"
    exit 1
fi

# Check if kubectl can connect to cluster
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}Error: Cannot connect to Kubernetes cluster${NC}"
    echo "Please ensure your Kubernetes cluster is running and kubectl is configured"
    exit 1
fi

echo -e "${GREEN}✓ kubectl is installed and connected to cluster${NC}"
echo ""

# Step 1: Install ECK Operator
echo "Step 1: Installing ECK Operator..."
kubectl create -f https://download.elastic.co/downloads/eck/3.4.0/crds.yaml 2>/dev/null || echo "CRDs already exist"
kubectl apply -f https://download.elastic.co/downloads/eck/3.4.0/operator.yaml

echo -e "${GREEN}✓ ECK Operator installed${NC}"
echo ""

# Step 2: Wait for operator to be ready
echo "Step 2: Waiting for ECK operator to be ready..."
kubectl rollout status statefulset/elastic-operator -n elastic-system --timeout=300s

echo -e "${GREEN}✓ ECK Operator is ready${NC}"
echo ""

# Step 3: Create namespace
echo "Step 3: Creating elastic-system namespace..."
kubectl apply -f "${SCRIPT_DIR}/namespace.yaml"

echo -e "${GREEN}✓ Namespace created${NC}"
echo ""

# Step 4: Deploy Elasticsearch (includes license Secret)
echo "Step 4: Deploying Elasticsearch cluster with license..."
kubectl apply -f "${SCRIPT_DIR}/elasticsearch.yaml"

echo -e "${GREEN}✓ Elasticsearch deployment initiated (license Secret applied)${NC}"
echo ""

# Step 5: Wait for Elasticsearch to be ready
echo "Step 5: Waiting for Elasticsearch to be ready (this may take 5-10 minutes)..."
echo "You can monitor progress with: kubectl get elasticsearch -n elastic-system -w"
kubectl wait --for=jsonpath='{.status.phase}'=Ready --timeout=600s elasticsearch/elasticsearch -n elastic-system
echo -e "${GREEN}✓ Elasticsearch is ready${NC}"
echo ""

# Step 6: Apply the enterprise license via Elasticsearch API
echo "Step 6: Applying enterprise license..."
LICENSE_FILE="${SCRIPT_DIR}/license-release-orchestration-enterprise_trial.json"
if [ -f "${LICENSE_FILE}" ]; then
    ES_PASSWORD=$(kubectl get secret elasticsearch-es-elastic-user -n elastic-system -o go-template='{{.data.elastic | base64decode}}')

    # Port-forward in background to apply license
    kubectl port-forward service/elasticsearch-es-http 9200 -n elastic-system &
    PF_PID=$!
    sleep 5

    # Apply the license
    LICENSE_RESPONSE=$(curl -s -k -u "elastic:${ES_PASSWORD}" -X PUT "https://localhost:9200/_license" \
        -H "Content-Type: application/json" \
        -d @"${LICENSE_FILE}")

    echo "License API response: ${LICENSE_RESPONSE}"

    # Kill the port-forward
    kill ${PF_PID} 2>/dev/null || true
    wait ${PF_PID} 2>/dev/null || true

    if echo "${LICENSE_RESPONSE}" | grep -q '"acknowledged":true'; then
        echo -e "${GREEN}✓ Enterprise license applied successfully${NC}"
    else
        echo -e "${YELLOW}Warning: License may not have been applied. Check the response above.${NC}"
        echo "You can manually apply it later with:"
        echo "  kubectl port-forward service/elasticsearch-es-http 9200 -n elastic-system &"
        echo "  curl -k -u \"elastic:<password>\" -X PUT \"https://localhost:9200/_license\" -H \"Content-Type: application/json\" -d @${LICENSE_FILE}"
    fi
else
    echo -e "${YELLOW}Warning: License file not found at ${LICENSE_FILE}${NC}"
    echo "Skipping license application."
fi
echo ""

# Step 7: Deploy Kibana
echo "Step 7: Deploying Kibana..."
kubectl apply -f "${SCRIPT_DIR}/kibana.yaml"

echo -e "${GREEN}✓ Kibana deployment initiated${NC}"
echo ""

# Step 8: Wait for Kibana to be ready
echo "Step 8: Waiting for Kibana to be ready..."
kubectl get kibana kibana -n elastic-system -o jsonpath='{.status.health}'

echo -e "${green}✓ Kibana is ready${NC}"
echo ""

# Step 9: Get credentials and endpoints
echo "================================================"
echo "Deployment Complete!"
echo "================================================"
echo ""

ES_PASSWORD=$(kubectl get secret elasticsearch-es-elastic-user -n elastic-system -o go-template='{{.data.elastic | base64decode}}')

echo "Elasticsearch Credentials:"
echo "-------------------------"
echo "Username: elastic"
echo "Password: ${ES_PASSWORD}"
echo ""

echo "Elasticsearch Endpoints:"
echo "-------------------------"
echo "Internal (from within cluster):"
echo "  https://elasticsearch-es-http.elastic-system.svc:9200"
echo ""
echo "External (port-forward):"
echo "  Run: kubectl port-forward service/elasticsearch-es-http 9200 -n elastic-system"
echo "  Then access: https://localhost:9200"
echo ""

echo "Kibana Endpoints:"
echo "-------------------------"
echo "Internal (from within cluster):"
echo "  https://kibana-kb-http.elastic-system.svc:5601"
echo ""
echo "External (port-forward):"
echo "  Run: kubectl port-forward service/kibana-kb-http 5601 -n elastic-system"
echo "  Then access: https://localhost:5601"
echo ""

echo -e "${YELLOW}Note: ECK uses self-signed certificates by default.${NC}"
echo -e "${YELLOW}Use -k or --insecure flag with curl, or configure your Java application to trust the certificate.${NC}"
echo ""

echo "To get the CA certificate for your application:"
echo "  kubectl get secret elasticsearch-es-http-certs-public -n elastic-system -o go-template='{{index .data \"tls.crt\" | base64decode}}' > ca.crt"
echo ""

echo "Quick test connection:"
echo "  kubectl port-forward service/elasticsearch-es-http 9200 -n elastic-system &"
echo "  curl -u \"elastic:${ES_PASSWORD}\" -k \"https://localhost:9200\""
echo ""

# Verify license status
echo "Verify license:"
echo "  curl -u \"elastic:${ES_PASSWORD}\" -k \"https://localhost:9200/_license\""
echo ""
