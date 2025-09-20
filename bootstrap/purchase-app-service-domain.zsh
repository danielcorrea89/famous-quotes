SUBS_ID="e7cbc1ca-744a-432a-b54b-dd8b5a2d2799"
RG_NAME="rg-app-domains"
DOMAIN_NAME="${var.project_domain}"

az account set --subscription "$SUBS_ID"
az group create -n "$RG_NAME" -l eastus 1>/dev/null

# Idempotent: only buy if not present already
EXISTS_ID=$(az resource list --resource-type Microsoft.DomainRegistration/domains \
  --query "[?name=='$DOMAIN_NAME'].id | [0]" -o tsv)

if [ -z "$EXISTS_ID" ]; then
  az appservice domain create \
    --resource-group "$RG_NAME" \
    --hostname "$DOMAIN_NAME" \
    --contact-info @"./contact.json" \
    --accept-terms
else
  echo "Domain already exists: $EXISTS_ID"
fi