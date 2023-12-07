locals {
  sync_base_path          = "sys/sync/destinations"
  destination_name        = "${var.name}-${var.region}-${random_id.this.hex}"
  delete_sync_destination = alltrue([var.delete_all_secret_associations, var.delete_sync_destination])

  associate_secrets = flatten([
    for app_name, secret in var.associate_secrets : [
      for secret_name in secret.secret_name : {
        app_name    = app_name
        mount       = secret.mount
        secret_name = secret_name
      }
    ]
  ])

  unassociate_secrets = flatten([
    for app_name, secret in var.unassociate_secrets : [
      for secret_name in secret.secret_name : {
        app_name    = app_name
        mount       = secret.mount
        secret_name = secret_name
      }
    ]
  ])
}

#######################################
#                                     #
#    AWS IAM USER - ACCESS KEY MGMT   #
#                                     #
#######################################

resource "random_id" "this" {
  byte_length = 8
}

module "iam_user_secretsync" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-user"
  version = "~> 5.32.0"

  name = local.destination_name

  create_iam_access_key         = false
  create_iam_user_login_profile = false
  create_user                   = true
  force_destroy                 = true
}

resource "aws_iam_access_key" "vault_secretsync" {
  user = module.iam_user_secretsync.iam_user_name

  lifecycle {
    create_before_destroy = true

    replace_triggered_by = [
      null_resource.rotate_access_key
    ]
  }
}

# Trigger access key rotation every 90 days
resource "time_rotating" "iam_user_secretsync_access_key" {
  rotation_days = 90
}

resource "null_resource" "rotate_access_key" {
  triggers = {
    rotating_id = time_rotating.iam_user_secretsync_access_key.id
  }
}

data "aws_iam_policy_document" "vault_ent_secrets_manager_access" {
  statement {
    sid = "VaultEntSecretsManagerAccess"
    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue",
      "secretsmanager:CreateSecret",
      "secretsmanager:PutSecretValue",
      "secretsmanager:UpdateSecret",
      "secretsmanager:UpdateSecretVersionStage",
      "secretsmanager:DeleteSecret",
      "secretsmanager:RestoreSecret",
      "secretsmanager:TagResource",
      "secretsmanager:UntagResource",
    ]
    resources = [
      "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:vault/*"
    ]
  }
}

module "iam_group_secretsync" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-group-with-policies"
  version = "~> 5.32.0"

  name         = "vault-ent-secret-sync-${random_id.this.hex}"
  create_group = true

  enable_mfa_enforcement = false
  group_users            = [module.iam_user_secretsync.iam_user_name]

  custom_group_policies = [
    {
      name   = "vault-ent-secret-sync-${random_id.this.hex}"
      policy = data.aws_iam_policy_document.vault_ent_secrets_manager_access.json
    }
  ]
}

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

resource "time_sleep" "wait_5_seconds" {
  create_duration = "5s"

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
    time_sleep.wait_5_seconds,
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
