# 📘 README – Famous Quotes Challenge  

## 🌟 Overview  
This project implements a **secure, resilient, cloud-native web app** on **Azure** that:  
- Returns a **random famous quote** from an **Azure SQL Database** 🎤  
- Seeds itself from a **Blob Storage JSON file** if the DB is empty 📦  
- Runs behind **Azure Front Door** with **custom domain + HTTPS** 🌍  
- Enforces **Private Link, VNet integration, and Managed Identity** 🔐  
- Built with **Terraform + .NET 8 (minimal API)** ⚡  

---

## 🏗️ Architecture  

```mermaid
flowchart TD
    subgraph Client 🌐
      Browser
    end

    subgraph Edge 🌍
      AFD[Azure Front Door 🌍] --> |Custom Domain myfamousquotes.net| Browser
      WAF[WAF 🔒]
      AFD --> WAF
    end

    subgraph AppTier ⚙️
      AppSvc[App Service 🚀]
      VNet[VNet Integration 🌐]
      PE[Private Endpoint 🔐]
      AFD --> AppSvc
      AppSvc --> VNet
      AppSvc --> PE
    end

    subgraph DataTier 💾
      SQL[(Azure SQL Database 📖)]
      Blob[(Blob Storage 📦 quotes.json)]
      PE --> SQL
      AppSvc --> SQL
      AppSvc --> Blob
    end
```

---

## ⚡ Bootstrap (One-time)  
Create Terraform state storage + optional domain purchase.  

```bash
# Variables
RESOURCE_GROUP="rg-terraform-state"
STORAGE_ACCOUNT="stfamousquotestfstate"
CONTAINER_NAME="tfstate"

# Create RG + Storage Account + Container
az group create -n $RESOURCE_GROUP -l australiaeast
az storage account create -n $STORAGE_ACCOUNT -g $RESOURCE_GROUP -l australiaeast --sku Standard_LRS
az storage container create -n $CONTAINER_NAME --account-name $STORAGE_ACCOUNT
```

*(Optional)* Purchase your custom domain in Azure App Service Domains, e.g. `myfamousquotes.net`.  

---

## 🚀 Deploy Infra  

```bash
cd infra
terraform init -backend-config="storage_account_name=stfamousquotestfstate"                -backend-config="container_name=tfstate"                -backend-config="resource_group_name=rg-terraform-state"
terraform apply
```

This provisions:  
- Resource groups  
- SQL Server + Database  
- App Service Plan (Linux) + App Service  
- VNet integration + Private Endpoints  
- Azure Front Door with **myfamousquotes.net** + redirect from `www.`  

---

## 📦 Upload Seed Quotes  

The app seeds from **Blob Storage** (`stfamousquotesdev` / container `seed` / file `quotes.json`).  

```bash
az storage container create   --account-name stfamousquotesdev   --name seed   --auth-mode login

az storage blob upload   --account-name stfamousquotesdev   --container-name seed   --name quotes.json   --file app/sql/quotes.json   --overwrite   --auth-mode login
```

---

## 🔑 Enable Managed Identity in SQL  

Run `app/sql/setup-managed-identity.sql` against:  
1. `master` DB (no-op, safe)  
2. `db-famousquotes-dev`  

```sql
CREATE USER [app-famousquotes-dev] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [app-famousquotes-dev];
ALTER ROLE db_datawriter ADD MEMBER [app-famousquotes-dev];
```

This gives the App Service MI least-privilege access.  

---

## 📤 Deploy App  

### 1. Publish & Zip  
```bash
dotnet publish -c Release -o publish app/src/FamousQuotes.Api
cd publish
zip -r ../famousquotes.zip .
cd ..
```

### 2. Deploy to Azure  
```bash
az webapp deployment source config-zip   --resource-group rg-famousquotes-dev   --name app-famousquotes-dev   --src famousquotes.zip
```

---

## ✅ Test  

```bash
curl https://myfamousquotes.net
```

Expected response:  
```json
{
  "id": 42,
  "text": "The only limit to our realization of tomorrow is our doubts of today.",
  "author": "F. D. Roosevelt",
  "source": "quotes.json"
}
```

Health probe:  
```bash
curl https://myfamousquotes.net/healthz
```

---

## 📊 Next Steps (>5h improvements)  

### Terraform State  
- [ ] Enable **ZRS redundancy** for tfstate storage (1.5h)  
- [ ] Add **immutability / soft delete** for blobs (1h)  
- [ ] Restrict access via **Private Endpoint** (2h)  

### Core Infra  
- [ ] Modularize: move **core infra** (network, SQL, App Service Plan, Front Door profile) into a **shared project** (2h)  
- [ ] Keep **app-specific slice** (domain, routes, app svc, MI) separate (1.5h)  
- [ ] Add **paired region App Service** for blue/green (3h)  

### Pipelines  
- [ ] GitHub Actions to:  
  - Run Terraform  
  - Deploy App  
  - Run SQL MI setup (via SPN)  

### Availability & Security  
- [ ] Zone redundant SQL (2h)  
- [ ] Add WAF rules (1.5h)  
- [ ] Add alerts + action groups (1h)  

---

## 🤖 How I Used AI  

- Generated **initial .NET app scaffolding**  
- Debugged **Terraform provider quirks** (Front Door associations, DNS auth)  
- Wrote **seed logic** for Blob + SQL  
- Discussed **design trade-offs** (private endpoints vs public, vnet integration)  
- Tracked **progress + time** like a virtual pair engineer  

**AI was a productivity multiplier** — but all code & infra were validated, tested, and fully understood.  

---

## ⏱️ Time Breakdown (~5h)  

| Hour | What I built |
|------|--------------|
| 1    | Terraform core (RG, SQL, ASP, App Service) |
| 2    | Front Door + custom domain + DNS validation |
| 3    | Private endpoints, MI, Blob setup |
| 4    | .NET app (Program.cs with seeding & random quotes) |
| 5    | Docs, monitoring, alert skeleton |

---

## 💰 Cost Estimate (dev env)  

- App Service Plan (P1v3): ~AUD 200/mo  
- Azure SQL (S0): ~AUD 20/mo  
- Storage: < AUD 5/mo  
- Front Door: ~AUD 30/mo  
- **Total: ~AUD 255/mo** (dev)  

Prod would scale with zone redundancy & multi-region.  
