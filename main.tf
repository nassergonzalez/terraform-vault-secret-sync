#######################################
#                                     #
#    VAULT SECRET SYNC MANAGEMENT     #
#                                     #
#######################################

# Create Vault -> AWS SM destination
# Only need to create one destination per AWS region
resource "vault_generic_endpoint" "create_destination_sync" {
  count = local.delete_sync_destination ? 0 : 1

  path = "${local.sync_base_path}/aws-sm/${local.destination_name}"

  data_json = jsonencode({
    access_key_id     = aws_iam_access_key.vault_secretsync.id
    secret_access_key = aws_iam_access_key.vault_secretsync.secret
    region            = var.region
  })

  disable_delete       = false # this works and removes the stuff but we need to make sure that all associations are removed first
  disable_read         = true
  ignore_absent_fields = true
}

resource "time_sleep" "wait_for_destination_sync" {
  create_duration = "10s"

  depends_on = [
    vault_generic_endpoint.create_destination_sync,
  ]
}

# Create Vault -> AWS SM association
# https://developer.hashicorp.com/vault/api-docs/system/secrets-sync#set-association
resource "vault_generic_endpoint" "create_association_sync" {
  for_each = { for secret in local.associate_secrets : "${secret.app_name}-${secret.secret_name}" => secret }

  path = "${local.sync_base_path}/aws-sm/${local.destination_name}/associations/set"

  data_json = jsonencode({
    mount       = each.value.mount
    secret_name = each.value.secret_name
  })

  disable_delete       = true
  disable_read         = true
  ignore_absent_fields = true

  depends_on = [
    time_sleep.wait_for_destination_sync,
  ]
}

# Remove Some Vault -> AWS SM association
resource "vault_generic_endpoint" "remove_some_association_sync" {
  for_each = { for secret in local.unassociate_secrets : "${secret.app_name}-${secret.secret_name}" => secret }

  path = "${local.sync_base_path}/aws-sm/${local.destination_name}/associations/remove"

  data_json = jsonencode({
    mount       = each.value.mount
    secret_name = each.value.secret_name
  })

  disable_delete       = true
  disable_read         = true
  ignore_absent_fields = true
}

# Remove ALL Vault -> AWS SM destination
resource "vault_generic_endpoint" "remove_all_association_sync" {
  for_each = var.delete_all_secret_associations ? { for secret in local.associate_secrets : "${secret.app_name}-${secret.secret_name}" => secret } : {}

  path = "${local.sync_base_path}/aws-sm/${local.destination_name}/associations/remove"

  data_json = jsonencode({
    mount       = each.value.mount
    secret_name = each.value.secret_name
  })

  disable_delete       = true
  disable_read         = true
  ignore_absent_fields = true
}
