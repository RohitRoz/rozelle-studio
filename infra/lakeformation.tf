# Lake Formation Phase 5a: admin settings + lakehouse location registration.
# Behavior-neutral: hybrid defaults (IAM_ALLOWED_PRINCIPALS) stay in place, so
# Gate 2 remains open until grants exist (Phase 5b, after the Piece 6 roles).

# Account+region singleton. REPLACES the whole settings object on apply — the
# admins list must always include the principal running Terraform, or LF
# administration (including this config) locks itself out.
resource "aws_lakeformation_data_lake_settings" "this" {
  admins = [data.aws_caller_identity.current.arn]

  # Keep hybrid mode: new databases/tables stay reachable via plain IAM.
  # Omitting these blocks would silently flip new objects to LF-enforced.
  create_database_default_permissions {
    principal   = "IAM_ALLOWED_PRINCIPALS"
    permissions = ["ALL"]
  }

  create_table_default_permissions {
    principal   = "IAM_ALLOWED_PRINCIPALS"
    permissions = ["ALL"]
  }
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
