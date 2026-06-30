output "bronze_bucket_name" {
  description = "Name of the bronze raw-landing S3 bucket."
  value       = aws_s3_bucket.bronze.id
}

output "bronze_bucket_arn" {
  description = "ARN of the bronze raw-landing S3 bucket."
  value       = aws_s3_bucket.bronze.arn
}

output "project_kms_key_arn" {
  description = "ARN of the single project CMK (bronze key, reused project-wide)."
  value       = aws_kms_key.bronze.arn
}

output "project_kms_key_alias" {
  description = "Alias of the project CMK."
  value       = aws_kms_alias.bronze.name
}
