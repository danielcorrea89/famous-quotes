
High Level Architecture

 Internet
   │
 Azure Front Door (Standard) + WAF
   │  (HTTPS)
 App Service (Linux, PremiumV3, Zone Redundant)
   │  (VNet integration)
 Virtual Network + Subnets
   ├─ Private Endpoint: Azure SQL
   └─ Private Endpoint: Key Vault

 Azure SQL (Serverless, GP)
 Azure Key Vault
 Azure Storage (Blob, private container with quotes seed)
 Application Insights + Log Analytics