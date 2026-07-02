output "bronze_bucket_name" {
  description = "Name of the bronze raw-landing S3 bucket."
  value       = module.bronze.bucket_id
}

output "bronze_bucket_arn" {
  description = "ARN of the bronze raw-landing S3 bucket."
  value       = module.bronze.bucket_arn
}

output "lakehouse_bucket_name" {
  description = "Name of the Iceberg data bucket (silver/gold)."
  value       = module.lakehouse.bucket_id
}

output "lakehouse_bucket_arn" {
  description = "ARN of the Iceberg data bucket."
  value       = module.lakehouse.bucket_arn
}

output "athena_results_bucket_name" {
  description = "Name of the Athena query-results bucket (workgroup output location)."
  value       = module.athena_results.bucket_id
}

output "athena_results_bucket_arn" {
  description = "ARN of the Athena query-results bucket."
  value       = module.athena_results.bucket_arn
}

output "project_kms_key_arn" {
  description = "ARN of the single project CMK (bronze key, reused project-wide)."
  value       = aws_kms_key.bronze.arn
}

output "project_kms_key_alias" {
  description = "Alias of the project CMK."
  value       = aws_kms_alias.bronze.name
}

output "glue_database_names" {
  description = "Glue Catalog database per dbt layer (staging/intermediate/marts)."
  value       = { for k, db in aws_glue_catalog_database.layers : k => db.name }
}

output "logs_bucket_name" {
  description = "Name of the S3 server-access-log bucket (SSE-S3)."
  value       = aws_s3_bucket.logs.id
}

output "logs_bucket_arn" {
  description = "ARN of the S3 server-access-log bucket."
  value       = aws_s3_bucket.logs.arn
}
