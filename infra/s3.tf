locals {
  bronze_bucket_name = "${var.project}-${var.environment}-bronze-${data.aws_caller_identity.current.account_id}"
}

module "bronze" {
  source = "./modules/secure_bucket"

  name        = local.bronze_bucket_name
  layer       = "bronze"
  kms_key_arn = aws_kms_key.bronze.arn

  # Bronze raw is allowed to tier (unlike Iceberg data buckets).
  transitions = [
    {
      days          = var.bronze_ia_transition_days
      storage_class = "STANDARD_IA"
    },
    {
      days          = var.bronze_glacier_transition_days
      storage_class = "GLACIER"
    },
  ]

  noncurrent_expiration_days = var.bronze_noncurrent_expiration_days
}

# Bronze was originally deployed as root-level resources; these map the existing
# state into the module without destroy/recreate.
moved {
  from = aws_s3_bucket.bronze
  to   = module.bronze.aws_s3_bucket.this
}

moved {
  from = aws_s3_bucket_public_access_block.bronze
  to   = module.bronze.aws_s3_bucket_public_access_block.this
}

moved {
  from = aws_s3_bucket_versioning.bronze
  to   = module.bronze.aws_s3_bucket_versioning.this
}

moved {
  from = aws_s3_bucket_server_side_encryption_configuration.bronze
  to   = module.bronze.aws_s3_bucket_server_side_encryption_configuration.this
}

moved {
  from = aws_s3_bucket_lifecycle_configuration.bronze
  to   = module.bronze.aws_s3_bucket_lifecycle_configuration.this
}

moved {
  from = aws_s3_bucket_policy.bronze
  to   = module.bronze.aws_s3_bucket_policy.this
}
