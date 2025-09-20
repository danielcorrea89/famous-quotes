variable "project_name" {
  type    = string
  default = "famousquotes"
}

variable "location" {
  type    = string
  default = "Australia East"
}

# variable "aad_admin_login" {
#   description = "AAD login (UPN) for SQL administrator"
#   type        = string
#   default = "sql-admins-famousquotes-dev"
# }

# variable "aad_admin_object_id" {
#   description = "AAD object ID for SQL administrator"
#   type        = string
#   default = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
# }