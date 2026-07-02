# Dedicated access-log bucket for S3 server access logs. Shared across data
# buckets via per-source prefixes. Encrypted with SSE-S3 (AES256), NOT the CMK:
# S3 server-access-log delivery to an S3 bucket does not support SSE-KMS. This is
# a deliberate, documented exception to the project's CMK-everywhere convention.

locals {
  logs_bucket_name = "${var.project}-${var.environment}-logs-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "logs" {
  bucket = local.logs_bucket_name

  tags = {
    Name  = local.logs_bucket_name
    Layer = "logs"
  }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket = aws_s3_bucket.logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ACLs disabled; the log-delivery service is granted via bucket policy instead.
resource "aws_s3_bucket_ownership_controls" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Logs may expire (unlike Iceberg data buckets).
resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "expire-access-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = var.access_log_retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "logs_bucket_policy" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.logs.arn,
      "${aws_s3_bucket.logs.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  # Allow the S3 server-access-log delivery service to write logs, scoped to the
  # source data buckets and this account (confused-deputy protection).
  statement {
    sid    = "S3ServerAccessLogsDelivery"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.logs.arn}/*"]

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values = [
        module.bronze.bucket_arn,
        module.lakehouse.bucket_arn,
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_s3_bucket_policy" "logs" {
  bucket     = aws_s3_bucket.logs.id
  policy     = data.aws_iam_policy_document.logs_bucket_policy.json
  depends_on = [aws_s3_bucket_public_access_block.logs]
}

# Enable server access logging on the data buckets. depends_on the log bucket
# policy so the delivery grant exists before S3 validates it. The Athena
# results bucket is deliberately not logged: it is high-churn scratch output,
# and query-level audit comes from Athena workgroup history + CloudTrail.
resource "aws_s3_bucket_logging" "bronze" {
  bucket = module.bronze.bucket_id

  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "s3-access-logs/bronze/"

  depends_on = [aws_s3_bucket_policy.logs]
}

resource "aws_s3_bucket_logging" "lakehouse" {
  bucket = module.lakehouse.bucket_id

  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "s3-access-logs/lakehouse/"

  depends_on = [aws_s3_bucket_policy.logs]
}
