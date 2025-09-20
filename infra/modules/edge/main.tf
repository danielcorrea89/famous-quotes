locals {
  apex_fqdn = var.apex_domain
  www_fqdn  = var.www_domain
}

# Front Door profile (Standard)
resource "azurerm_cdn_frontdoor_profile" "profile" {
  name                = "fdp-${var.project_name}-dev"
  resource_group_name = var.resource_group_name
  sku_name            = "Standard_AzureFrontDoor"
}

# Endpoint
resource "azurerm_cdn_frontdoor_endpoint" "endpoint" {
  name                     = "fde-${var.project_name}-dev"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.profile.id
}
# Second endpoint dedicated to www redirect
resource "azurerm_cdn_frontdoor_endpoint" "endpoint_www" {
  name                     = "fde-${var.project_name}-www-dev"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.profile.id
}

# Origin Group
resource "azurerm_cdn_frontdoor_origin_group" "og" {
  name                     = "og-web"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.profile.id

  session_affinity_enabled = false

  health_probe {
    path                = "/"
    protocol            = "Https"
    request_type        = "GET"
    interval_in_seconds = 30
  }

  load_balancing {
    sample_size                        = 4
    successful_samples_required        = 3
    additional_latency_in_milliseconds = 0
  }
}

# Origin (points to App Service)
resource "azurerm_cdn_frontdoor_origin" "origin" {
  name                           = "web-origin"
  cdn_frontdoor_origin_group_id  = azurerm_cdn_frontdoor_origin_group.og.id

  host_name                      = var.origin_hostname
  origin_host_header             = var.origin_hostname
  http_port                      = 80
  https_port                     = 443
  priority                       = 1
  weight                         = 1000
  certificate_name_check_enabled = true
  enabled                        = true
}

# -------------------------
# Custom domains (apex + www) with managed TLS
# -------------------------
resource "azurerm_cdn_frontdoor_custom_domain" "apex" {
  name                     = replace(local.apex_fqdn, ".", "-")
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.profile.id
  host_name                = local.apex_fqdn

  tls {
    certificate_type    = "ManagedCertificate"
  }
}

resource "azurerm_cdn_frontdoor_custom_domain" "www" {
  name                     = replace(local.www_fqdn, ".", "-")
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.profile.id
  host_name                = local.www_fqdn

  tls {
    certificate_type    = "ManagedCertificate"
  }
}

# -------------------------
# Azure DNS records for validation + resolution
# -------------------------
# TXT validations (_dnsauth and _dnsauth.www)
resource "azurerm_dns_txt_record" "_dnsauth_apex" {
  name                = "_dnsauth"
  zone_name           = var.zone_name
  resource_group_name = var.dns_zone_resource_group
  ttl                 = 300
  record { value = azurerm_cdn_frontdoor_custom_domain.apex.validation_token }
}

resource "azurerm_dns_txt_record" "_dnsauth_www" {
  name                = "_dnsauth.www"
  zone_name           = var.zone_name
  resource_group_name = var.dns_zone_resource_group
  ttl                 = 300
  record { value = azurerm_cdn_frontdoor_custom_domain.www.validation_token }
}

# Apex alias (A + AAAA) -> Front Door endpoint (Azure DNS "alias" to resource ID)
resource "azurerm_dns_a_record" "apex_alias_a" {
  name                = "@"
  zone_name           = var.zone_name
  resource_group_name = var.dns_zone_resource_group
  ttl                 = 300
  target_resource_id  = azurerm_cdn_frontdoor_endpoint.endpoint.id
}


# www CNAME -> FD endpoint hostname
resource "azurerm_dns_cname_record" "www_cname" {
  name                = "www"
  zone_name           = var.zone_name
  resource_group_name = var.dns_zone_resource_group
  ttl                 = 300
  record              = azurerm_cdn_frontdoor_endpoint.endpoint_www.host_name  # <-- changed
}

# -------------------------
# Routes
# -------------------------
# Main route serving the apex (non-www)
resource "azurerm_cdn_frontdoor_route" "apex_route" {
  name                          = "route-apex"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.endpoint.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.og.id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.origin.id]

  supported_protocols     = ["Http", "Https"]
  https_redirect_enabled  = true
  forwarding_protocol     = "HttpsOnly"
  patterns_to_match       = ["/*"]
  cdn_frontdoor_custom_domain_ids = [ azurerm_cdn_frontdoor_custom_domain.apex.id ]
  
   depends_on = [
    azurerm_cdn_frontdoor_custom_domain.apex,
    azurerm_cdn_frontdoor_endpoint.endpoint,
    azurerm_cdn_frontdoor_origin_group.og,
    azurerm_cdn_frontdoor_origin.origin
  ]
}


# Rule set that redirects any requests to the apex (used by the www route)
resource "azurerm_cdn_frontdoor_rule_set" "www_redirect_rs" {
  name                     = "rswwwredirect"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.profile.id
}

resource "azurerm_cdn_frontdoor_rule" "www_redirect_rule" {
  name                      = "rwwwredirect"
  cdn_frontdoor_rule_set_id = azurerm_cdn_frontdoor_rule_set.www_redirect_rs.id
  order                     = 1

  actions {
    url_redirect_action {
      redirect_type        = "Moved"           # 301
      redirect_protocol    = "Https"
      destination_hostname = local.apex_fqdn
    }
  }
}

# Route for www that attaches the redirect rule set
resource "azurerm_cdn_frontdoor_route" "www_route" {
  name                          = "route-www"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.endpoint_www.id  # <-- changed
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.og.id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.origin.id]

  supported_protocols    = ["Http", "Https"]
  https_redirect_enabled = true
  patterns_to_match      = ["/*"]
  cdn_frontdoor_rule_set_ids = [azurerm_cdn_frontdoor_rule_set.www_redirect_rs.id]
  cdn_frontdoor_custom_domain_ids = [ azurerm_cdn_frontdoor_custom_domain.www.id ]

  depends_on = [
    azurerm_cdn_frontdoor_custom_domain.www,
    azurerm_cdn_frontdoor_endpoint.endpoint_www,
    azurerm_cdn_frontdoor_origin_group.og,
    azurerm_cdn_frontdoor_origin.origin
  ]
}


# WAF policy (Standard/Premium AFD)
resource "azurerm_cdn_frontdoor_firewall_policy" "waf" {
  name                = "waf${var.project_name}dev"
  resource_group_name = var.resource_group_name
  sku_name            = "Standard_AzureFrontDoor"
  mode                = "Prevention"

  managed_rule {
    type    = "DefaultRuleSet"
    version = "2.0"
    action = "Block"
  }

  # Optional: enable bot ruleset
  managed_rule {
    type    = "Microsoft_BotManagerRuleSet"
    version = "1.0"
    action  = "Block"
  }
}

resource "azurerm_cdn_frontdoor_security_policy" "waf_assoc" {
  name                                  = "sp-${var.project_name}-dev"
  cdn_frontdoor_profile_id              = azurerm_cdn_frontdoor_profile.profile.id
  security_policies {
    firewall {
      cdn_frontdoor_firewall_policy_id  = azurerm_cdn_frontdoor_firewall_policy.waf.id
      association {
        domain {
          cdn_frontdoor_domain_id       = azurerm_cdn_frontdoor_custom_domain.apex.id
        }
        domain {
          cdn_frontdoor_domain_id       = azurerm_cdn_frontdoor_custom_domain.www.id
        }
        patterns_to_match = ["/*"]
      }
    }
  }

  depends_on = [
    azurerm_cdn_frontdoor_custom_domain.apex,
    azurerm_cdn_frontdoor_custom_domain.www
  ]
}

# Outputs
output "frontdoor_endpoint_hostname" { value = azurerm_cdn_frontdoor_endpoint.endpoint.host_name }
output "apex_fqdn"                   { value = local.apex_fqdn }
output "www_fqdn"                    { value = local.www_fqdn }