
set -e
set -u
set -o pipefail

# ========= CONFIG (edit if you want) =========
SUBS_ID="e7cbc1ca-744a-432a-b54b-dd8b5a2d2799"   # REPLACE HERE with your Subscription ID
LOCATION="australiaeast"
RG_NAME="rg-terraform-state"
ACCOUNT_NAME="stfamousquotestfstate"            # must be lowercase + globally unique
CONTAINER_NAME="tfstate"
# ============================================

log()  { print -P "%F{green}>>%f $*"; }
warn() { print -P "%F{yellow}!!%f $*"; }
die()  { print -P "%F{red}xx%f $*"; exit 1; }

command -v az >/dev/null 2>&1 || die "Azure CLI not found. Install with: brew install azure-cli"

# Let az auto-install needed extensions without prompting (zsh-safe)
az config set extension.use_dynamic_install=yes_without_prompt >/dev/null

log "Setting subscription to $SUBS_ID"
az account set --subscription "$SUBS_ID"
az account show --query '{name:name,id:id,tenant:tenantId}' -o table

# Ensure Microsoft.Storage provider is registered (avoids weird SubscriptionNotFound paths)
STATE="$(az provider show -n Microsoft.Storage --query registrationState -o tsv 2>/dev/null || echo Unknown)"
if [[ "$STATE" != "Registered" ]]; then
  log "Registering provider Microsoft.Storage (current: $STATE)"
  az provider register -n Microsoft.Storage >/dev/null
  # poll until registered
  for i in {1..40}; do
    STATE="$(az provider show -n Microsoft.Storage --query registrationState -o tsv 2>/dev/null || echo Unknown)"
    [[ "$STATE" == "Registered" ]] && break
    sleep 2
  done
fi
log "Provider Microsoft.Storage: $STATE"

# Resource group (create if missing)
if az group show -n "$RG_NAME" -o none 2>/dev/null; then
  log "RG exists: $RG_NAME"
else
  log "Creating RG: $RG_NAME"
  az group create -n "$RG_NAME" -l "$LOCATION" -o none
fi

# Storage account (create if missing)
if az storage account show -n "$ACCOUNT_NAME" -g "$RG_NAME" --subscription "$SUBS_ID" -o none 2>/dev/null; then
  log "Storage account exists: $ACCOUNT_NAME"
else
  log "Creating storage account: $ACCOUNT_NAME"
  az storage account create \
    -n "$ACCOUNT_NAME" \
    -g "$RG_NAME" \
    -l "$LOCATION" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --min-tls-version TLS1_2 \
    --https-only true \
    --allow-blob-public-access false \
    --subscription "$SUBS_ID" -o none
fi

# Use an account key for container ops (works even if you don't have data-plane RBAC)
ACCOUNT_KEY="$(az storage account keys list \
  --account-name "$ACCOUNT_NAME" \
  -g "$RG_NAME" \
  --subscription "$SUBS_ID" \
  --query '[0].value' -o tsv)"

# Container (create if missing)
if az storage container exists \
     --account-name "$ACCOUNT_NAME" \
     --account-key "$ACCOUNT_KEY" \
     --name "$CONTAINER_NAME" \
     --query exists -o tsv | grep -q true; then
  log "Container exists: $CONTAINER_NAME"
else
  log "Creating container: $CONTAINER_NAME"
  az storage container create \
    --account-name "$ACCOUNT_NAME" \
    --account-key "$ACCOUNT_KEY" \
    --name "$CONTAINER_NAME" -o none
fi

print
log "✅ Backend resources ready."
print
print -- "Paste this into infra/envs/dev/providers.tf:"
cat <<EOF

terraform {
  required_version = ">= 1.7.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.109.0"
    }
  }
  backend "azurerm" {
    subscription_id      = "$SUBS_ID"
    resource_group_name  = "$RG_NAME"
    storage_account_name = "$ACCOUNT_NAME"
    container_name       = "$CONTAINER_NAME"
    key                  = "dev.terraform.tfstate"
  }
}
provider "azurerm" { features {} }
EOF
