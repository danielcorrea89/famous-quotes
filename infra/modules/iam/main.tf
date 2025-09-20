variable "group_display_name" { type = string }
variable "initial_member_object_ids" {
  type    = list(string)
  default = []
}

resource "azuread_group" "sql_admins" {
  display_name       = var.group_display_name
  security_enabled   = true
  mail_enabled       = false
  assignable_to_role = false
}

# IMPORTANT: use object_id (bare GUID), not id
resource "azuread_group_member" "members" {
  for_each         = toset(var.initial_member_object_ids)
  group_object_id  = azuread_group.sql_admins.object_id
  member_object_id = each.value
}

# Outputs (expose the bare GUID)
output "sql_admin_group_object_id"   { value = azuread_group.sql_admins.object_id }
output "sql_admin_group_displayname" { value = azuread_group.sql_admins.display_name }