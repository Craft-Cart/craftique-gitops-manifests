#!/bin/bash
# GCP Secret Manager Setup Script
# This script automates the setup of GCP Secret Manager with External Secrets Operator

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== GCP Secret Manager Setup ===${NC}\n"

# Check prerequisites
echo "Checking prerequisites..."

if ! command -v gcloud &> /dev/null; then
    echo -e "${RED}ERROR: gcloud CLI not found. Please install it first.${NC}"
    echo "Visit: https://cloud.google.com/sdk/docs/install"
    exit 1
fi

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}ERROR: kubectl not found. Please install it first.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Prerequisites OK${NC}\n"

# Get GCP Project ID
read -p "Enter your GCP Project ID: " PROJECT_ID
if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}ERROR: Project ID cannot be empty${NC}"
    exit 1
fi

echo -e "\n${YELLOW}Setting GCP project to: $PROJECT_ID${NC}"
gcloud config set project $PROJECT_ID

# Enable Secret Manager API
echo -e "\n${YELLOW}Enabling Secret Manager API...${NC}"
gcloud services enable secretmanager.googleapis.com
echo -e "${GREEN}✓ API enabled${NC}"

# Create secrets in GCP
echo -e "\n${YELLOW}Creating secrets in GCP Secret Manager...${NC}"

# Generate strong password
POSTGRES_PASSWORD=$(openssl rand -base64 32)
echo -n "$POSTGRES_PASSWORD" | gcloud secrets create craftique-postgres-password \
    --data-file=- \
    --replication-policy="automatic" 2>/dev/null || \
    echo -e "${YELLOW}Secret already exists, skipping...${NC}"

echo -n "craftique" | gcloud secrets create craftique-postgres-user \
    --data-file=- \
    --replication-policy="automatic" 2>/dev/null || \
    echo -e "${YELLOW}Secret already exists, skipping...${NC}"

echo -n "craftique" | gcloud secrets create craftique-postgres-db \
    --data-file=- \
    --replication-policy="automatic" 2>/dev/null || \
    echo -e "${YELLOW}Secret already exists, skipping...${NC}"

echo -e "${GREEN}✓ Secrets created${NC}"
gcloud secrets list

# Create service account
echo -e "\n${YELLOW}Creating service account...${NC}"
gcloud iam service-accounts create external-secrets-operator \
    --display-name="External Secrets Operator" 2>/dev/null || \
    echo -e "${YELLOW}Service account already exists, skipping...${NC}"

# Grant permissions
echo -e "${YELLOW}Granting Secret Manager access...${NC}"
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:external-secrets-operator@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/secretmanager.secretAccessor" \
    --condition=None

# Create service account key
echo -e "\n${YELLOW}Creating service account key...${NC}"
if [ -f "gcp-key.json" ]; then
    echo -e "${YELLOW}Key file already exists. Delete it first if you want to regenerate.${NC}"
else
    gcloud iam service-accounts keys create gcp-key.json \
        --iam-account=external-secrets-operator@${PROJECT_ID}.iam.gserviceaccount.com
    echo -e "${GREEN}✓ Key created: gcp-key.json${NC}"
    echo -e "${RED}⚠️  IMPORTANT: Never commit gcp-key.json to Git!${NC}"
fi

# Deploy External Secrets Operator
echo -e "\n${YELLOW}Deploying External Secrets Operator...${NC}"
kubectl apply -f infrastructure/external-secrets/external-secrets-operator.yaml

echo "Waiting for operator to be ready..."
kubectl wait --for=condition=available --timeout=120s \
    deployment/external-secrets -n external-secrets || \
    echo -e "${YELLOW}Warning: Timeout waiting for operator. Check with: kubectl get pods -n external-secrets${NC}"

# Create Kubernetes secret with GCP key
echo -e "\n${YELLOW}Creating Kubernetes secret with GCP service account key...${NC}"
kubectl create secret generic gcp-secret-manager-key \
    -n external-secrets \
    --from-file=key.json=gcp-key.json \
    --dry-run=client -o yaml | kubectl apply -f -

echo -e "${GREEN}✓ Secret created${NC}"

# Update SecretStore with project ID
echo -e "\n${YELLOW}Updating SecretStore configuration...${NC}"
sed -i.bak "s/YOUR_GCP_PROJECT_ID/$PROJECT_ID/" infrastructure/external-secrets/gcp-secretstore.yaml
echo -e "${GREEN}✓ Updated gcp-secretstore.yaml with project ID: $PROJECT_ID${NC}"

# Deploy SecretStore
echo -e "\n${YELLOW}Deploying SecretStore...${NC}"
kubectl apply -f infrastructure/external-secrets/gcp-secretstore.yaml

# Wait a bit for SecretStore to initialize
sleep 5

# Deploy ExternalSecret
echo -e "\n${YELLOW}Deploying ExternalSecret...${NC}"
kubectl apply -f infrastructure/postgres/postgres-externalsecret.yaml

# Wait for sync
echo -e "\n${YELLOW}Waiting for secret sync (30 seconds)...${NC}"
sleep 30

# Verify
echo -e "\n${GREEN}=== Verification ===${NC}"
echo -e "\n1. ExternalSecret status:"
kubectl get externalsecret postgres-credentials

echo -e "\n2. Kubernetes Secret:"
kubectl get secret postgres-credentials

echo -e "\n3. SecretStore status:"
kubectl get secretstore gcp-secret-manager

# Final instructions
echo -e "\n${GREEN}=== Setup Complete! ===${NC}"
echo -e "\nNext steps:"
echo -e "1. ${YELLOW}Verify the secret:${NC}"
echo -e "   kubectl describe externalsecret postgres-credentials"
echo -e "\n2. ${YELLOW}Deploy your applications:${NC}"
echo -e "   kubectl apply -f infrastructure/postgres/"
echo -e "   kubectl apply -f apps/backend/"
echo -e "\n3. ${YELLOW}IMPORTANT: Secure your key file${NC}"
echo -e "   ${RED}Delete gcp-key.json after setup or store it securely (NOT in Git!)${NC}"
echo -e "\n4. ${YELLOW}Commit changes:${NC}"
echo -e "   git add ."
echo -e "   git commit -m 'feat: integrate GCP Secret Manager'"
echo -e "   git push"

echo -e "\n${GREEN}Cost: \$0/month (within GCP free tier)${NC}"
echo -e "\nFor troubleshooting, see: GCP-SECRETS-SETUP.md"
