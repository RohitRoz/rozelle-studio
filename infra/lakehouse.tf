locals {
  lakehouse_bucket_name      = "${var.project}-${var.environment}-lakehouse-${data.aws_caller_identity.current.account_id}"
  athena_results_bucket_name = "${var.project}-${var.environment}-athena-results-${data.aws_caller_identity.current.account_id}"
}

# Iceberg data bucket (silver/gold). NO tiering/expiration lifecycle rules:
# Iceberg tracks live files via snapshot metadata; S3 lifecycle acting on age
# would corrupt tables. Storage is reclaimed via OPTIMIZE/VACUUM (Piece 10).
module "lakehouse" {
  source = "./modules/secure_bucket"

  name        = local.lakehouse_bucket_name
  layer       = "lakehouse"
  kms_key_arn = aws_kms_key.bronze.arn
}

# Athena query-results bucket (workgroup output location, Piece 4). Transient
# scratch data: results expire aggressively; anything is re-runnable.
module "athena_results" {
  source = "./modules/secure_bucket"

  name        = local.athena_results_bucket_name
  layer       = "athena-results"
  kms_key_arn = aws_kms_key.bronze.arn

  expiration_days            = var.athena_results_expiration_days
  noncurrent_expiration_days = var.athena_results_expiration_days
}
