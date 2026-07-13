# Lake Formation Phase 5a: admin settings + lakehouse location registration.
# Behavior-neutral: hybrid defaults (IAM_ALLOWED_PRINCIPALS) stay in place, so
# Gate 2 remains open until grants exist (Phase 5b, after the Piece 6 roles).

# Account+region singleton. REPLACES the whole settings object on apply — the
# admins list must always include the principal running Terraform, or LF
# administration (including this config) locks itself out.
#
# Phase 5b — enforcement is imperative, documented here because it can't be
# Terraform state:
#  1. The provider treats omitted default-permission blocks as computed (keep
#     existing), so full-LF-mode defaults were set via
#     `aws lakeformation put-data-lake-settings` with empty
#     CreateDatabase/CreateTableDefaultPermissions (admins list preserved).
#  2. Pre-existing per-database open-door grants were revoked:
#     aws lakeformation revoke-permissions --principal DataLakePrincipalIdentifier=IAM_ALLOWED_PRINCIPALS \
#       --permissions ALL --resource '{"Database":{"Name":"<db>"}}'
resource "aws_lakeformation_data_lake_settings" "this" {
  admins = [data.aws_caller_identity.current.arn]
}

# Custom registration role. The service-linked role can't be used here: it has
# no permissions on the project CMK, and the lakehouse bucket is SSE-KMS —
# credential vending would fail on kms:Decrypt.
data "aws_iam_policy_document" "lf_register_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lakeformation.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

data "aws_iam_policy_document" "lf_register_permissions" {
  statement {
    sid    = "LakehouseObjectAccess"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]

    resources = ["${module.lakehouse.bucket_arn}/*"]
  }

  statement {
    sid    = "LakehouseBucketAccess"
    effect = "Allow"

    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]

    resources = [module.lakehouse.bucket_arn]
  }

  statement {
    sid    = "ProjectCMKAccess"
    effect = "Allow"

    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]

    resources = [aws_kms_key.bronze.arn]
  }
}

resource "aws_iam_role" "lf_register" {
  name               = "${var.project}-${var.environment}-lf-register"
  description        = "Lake Formation credential-vending role for the lakehouse bucket (S3 + CMK)."
  assume_role_policy = data.aws_iam_policy_document.lf_register_trust.json
}

resource "aws_iam_role_policy" "lf_register" {
  name   = "lakehouse-s3-kms"
  role   = aws_iam_role.lf_register.id
  policy = data.aws_iam_policy_document.lf_register_permissions.json
}

# Register the lakehouse bucket as governed data lake territory. Bronze, logs
# and athena-results are deliberately NOT registered (not lake data).
resource "aws_lakeformation_resource" "lakehouse" {
  arn      = module.lakehouse.bucket_arn
  role_arn = aws_iam_role.lf_register.arn

  # IAM policy attachment is eventually consistent; make sure the role can
  # actually be validated/assumed by LF at registration time.
  depends_on = [aws_iam_role_policy.lf_register]
}

# --- Phase 5b: grants (Gate 2 access) ----------------------------------------
# Grantees: the dbt role (transform) and the deployer user. LF admins can
# manage grants but get NO implicit data access — without the deployer grants,
# admin smoke tests would fail once IAM_ALLOWED_PRINCIPALS is revoked.
# The worker role gets nothing: it never touches the catalog.

locals {
  lf_grantees = {
    dbt      = aws_iam_role.dbt.arn
    deployer = data.aws_caller_identity.current.arn
  }

  # principal × database pairs for the two per-database grant sets
  lf_grants = {
    for pair in setproduct(keys(local.lf_grantees), keys(aws_glue_catalog_database.layers)) :
    "${pair[0]}-${pair[1]}" => {
      principal = local.lf_grantees[pair[0]]
      database  = aws_glue_catalog_database.layers[pair[1]].name
    }
  }
}

# Database-level: create/manage tables within the three layer namespaces.
resource "aws_lakeformation_permissions" "database" {
  for_each = local.lf_grants

  principal   = each.value.principal
  permissions = ["CREATE_TABLE", "ALTER", "DROP", "DESCRIBE"]

  database {
    name = each.value.database
  }
}

# Table-level (wildcard = all current and future tables in the database).
# MERGE compiles to INSERT + DELETE under Iceberg semantics.
resource "aws_lakeformation_permissions" "tables" {
  for_each = local.lf_grants

  principal   = each.value.principal
  permissions = ["SELECT", "INSERT", "DELETE", "ALTER", "DROP", "DESCRIBE"]

  table {
    database_name = each.value.database
    wildcard      = true
  }
}

# Creating tables that point at governed S3 requires explicit location access.
resource "aws_lakeformation_permissions" "data_location" {
  for_each = local.lf_grantees

  principal   = each.value
  permissions = ["DATA_LOCATION_ACCESS"]

  data_location {
    arn = aws_lakeformation_resource.lakehouse.arn
  }
}
