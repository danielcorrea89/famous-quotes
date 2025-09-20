variable "project_name"        { type = string }
variable "resource_group_name" { type = string }
variable "origin_hostname"     { type = string } # e.g. app-famousquotes-dev.azurewebsites.net

# DNS zone you already own in Azure DNS
variable "zone_name"               { type = string } # e.g. "${var.project_domain}"
variable "dns_zone_resource_group" { type = string } # RG containing the DNS zone

# Hostnames
variable "apex_domain" { type = string } # e.g. "${var.project_domain}"
variable "www_domain"  { type = string } # e.g. "www.${var.project_domain}"