data "aws_caller_identity" "current" {}

resource "aws_kms_key" "bronze" {
  description             = "${var.project} project CMK (bronze + reused project-wide)"
  deletion_window_in_days = var.kms_deletion_window_days
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableIAMUserPermissions"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      }
    ]
  })
}

resource "aws_kms_alias" "bronze" {
  name          = "alias/${var.project}-${var.environment}"
  target_key_id = aws_kms_key.bronze.key_id
}
