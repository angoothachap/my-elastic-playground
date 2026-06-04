#!/bin/bash

set -e

echo "================================================"
echo "ECK Uninstallation"
echo "================================================"
echo ""

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${YELLOW}WARNING: This will delete all Elasticsearch and Kibana resources!${NC}"
echo -e "${YELLOW}All data will be lost.${NC}"
echo ""
read -p "Are you sure you want to continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Uninstallation cancelled."
    exit 0
fi

echo ""
echo "Step 1: Deleting Kibana..."
kubectl delete -f kibana.yaml --ignore-not-found=true
echo -e "${GREEN}✓ Kibana deleted${NC}"
echo ""

echo "Step 2: Deleting Elasticsearch..."
kubectl delete -f elasticsearch.yaml --ignore-not-found=true
echo -e "${GREEN}✓ Elasticsearch deleted${NC}"
echo ""

echo "Step 3: Waiting for resources to be cleaned up..."
sleep 10

echo "Step 4: Deleting namespace..."
kubectl delete -f namespace.yaml --ignore-not-found=true
echo -e "${GREEN}✓ Namespace deleted${NC}"
echo ""

read -p "Do you want to uninstall the ECK operator as well? (yes/no): " uninstall_operator

if [ "$uninstall_operator" = "yes" ]; then
    echo ""
    echo "Step 5: Uninstalling ECK operator..."
    kubectl delete -f https://download.elastic.co/downloads/eck/2.15.0/operator.yaml --ignore-not-found=true
    kubectl delete -f https://download.elastic.co/downloads/eck/2.15.0/crds.yaml --ignore-not-found=true
    echo -e "${GREEN}✓ ECK operator uninstalled${NC}"
fi

echo ""
echo "================================================"
echo "Uninstallation Complete!"
echo "================================================"
