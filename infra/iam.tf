# Pipeline roles: dbt (transform) and worker (ingestion). Blast-radius split:
# ingestion can only write raw files to bronze; transform can only build tables
# through the workgroup. Trust = the deployer user for now (assume-role for
# local dbt dev + least-privilege testing); Pieces 9/10 append service
# principals (ecs-tasks / lambda / MWAA) when the compute exists.

data "aws_iam_policy_document" "assumable_by_deployer" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [data.aws_caller_identity.current.arn]
    }
  }
}

# --- dbt (transform) role ---------------------------------------------------

resource "aws_iam_role" "dbt" {
  name               = "${var.project}-${var.environment}-dbt"
  description        = "dbt transform role: Athena (pipeline workgroup only) + Glue tables in the three layer databases + medallion-scoped S3 + CMK."
  assume_role_policy = data.aws_iam_policy_document.assumable_by_deployer.json
}

data "aws_iam_policy_document" "dbt_permissions" {
  # Queries only through the pipeline workgroup: scan cutoff + enforced result
  # encryption (Piece 4) become inescapable for dbt.
  statement {
    sid    = "AthenaPipelineWorkgroup"
    effect = "Allow"

    actions = [
      "athena:StartQueryExecution",
      "athena:GetQueryExecution",
      "athena:GetQueryResults",
      "athena:StopQueryExecution",
      "athena:GetWorkGroup",
      "athena:BatchGetQueryExecution",
    ]

    resources = [aws_athena_workgroup.pipeline.arn]
  }

  # Table lifecycle inside the three layer databases only. No CreateDatabase:
  # Terraform owns namespaces, dbt owns tables.
  statement {
    sid    = "GlueTableLifecycle"
    effect = "Allow"

    actions = [
      "glue:GetDatabase",
      "glue:GetDatabases",
      "glue:GetTable",
      "glue:GetTables",
      "glue:CreateTable",
      "glue:UpdateTable",
      "glue:DeleteTable",
      "glue:GetPartition",
      "glue:GetPartitions",
      "glue:BatchGetPartition",
      "glue:CreatePartition",
      "glue:BatchCreatePartition",
      "glue:UpdatePartition",
      "glue:DeletePartition",
      "glue:BatchDeletePartition",
    ]

    resources = concat(
      ["arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:catalog"],
      [for db in aws_glue_catalog_database.layers : db.arn],
      [for db in aws_glue_catalog_database.layers :
        "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${db.name}/*"
      ],
    )
  }

  # Bronze is read-only for transform: the immutable source of truth.
  statement {
    sid    = "BronzeReadOnly"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]

    resources = [
      module.bronze.bucket_arn,
      "${module.bronze.bucket_arn}/*",
    ]
  }

  # Direct lakehouse + results access: required while LF is in hybrid mode
  # (Athena reads/writes S3 with the caller's credentials). Post-5b, lakehouse
  # access can shrink in favor of LF credential vending.
  statement {
    sid    = "LakehouseAndResultsReadWrite"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:ListBucketMultipartUploads",
      "s3:ListMultipartUploadParts",
      "s3:AbortMultipartUpload",
    ]

    resources = [
      module.lakehouse.bucket_arn,
      "${module.lakehouse.bucket_arn}/*",
      module.athena_results.bucket_arn,
      "${module.athena_results.bucket_arn}/*",
    ]
  }

  statement {
    sid    = "ProjectCMKUse"
    effect = "Allow"

    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]

    resources = [aws_kms_key.bronze.arn]
  }

  # Credential-vending entry point. Inert in hybrid mode; required once Phase
  # 5b enforces Gate 2. No resource-level scoping supported.
  statement {
    sid       = "LakeFormationDataAccess"
    effect    = "Allow"
    actions   = ["lakeformation:GetDataAccess"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "dbt" {
  name   = "transform-permissions"
  role   = aws_iam_role.dbt.id
  policy = data.aws_iam_policy_document.dbt_permissions.json
}

# --- worker (ingestion) role ------------------------------------------------

resource "aws_iam_role" "worker" {
  name               = "${var.project}-${var.environment}-worker"
  description        = "Ingestion role: write-only raw landing into bronze raw/ prefix. SQS (Piece 7) and Secrets Manager (Piece 8) statements appended later."
  assume_role_policy = data.aws_iam_policy_document.assumable_by_deployer.json
}

data "aws_iam_policy_document" "worker_permissions" {
  # Write-only, prefix-scoped: no read, no delete. Versioning (Piece 1) plus
  # this means ingestion cannot destroy bronze history.
  statement {
    sid    = "BronzeRawWriteOnly"
    effect = "Allow"

    actions = [
      "s3:PutObject",
      "s3:AbortMultipartUpload",
    ]

    resources = ["${module.bronze.bucket_arn}/raw/*"]
  }

  # Encrypt-on-write only; no Decrypt until something proves it needs to read.
  statement {
    sid    = "ProjectCMKEncryptOnly"
    effect = "Allow"

    actions = [
      "kms:GenerateDataKey*",
    ]

    resources = [aws_kms_key.bronze.arn]
  }
}

resource "aws_iam_role_policy" "worker" {
  name   = "ingestion-permissions"
  role   = aws_iam_role.worker.id
  policy = data.aws_iam_policy_document.worker_permissions.json
}
