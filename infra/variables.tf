variable "project" {
  description = "Project name; used as a prefix for resource names and tags."
  type        = string
  default     = "music-pipeline"
}

variable "environment" {
  description = "Deployment environment (e.g. dev, prod)."
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
  default     = "us-east-1"
}

variable "kms_deletion_window_days" {
  description = "Waiting period (days) before the project CMK is deleted after scheduling deletion."
  type        = number
  default     = 30

  validation {
    condition     = var.kms_deletion_window_days >= 7 && var.kms_deletion_window_days <= 30
    error_message = "kms_deletion_window_days must be between 7 and 30."
  }
}

variable "bronze_ia_transition_days" {
  description = "Days after which current bronze objects transition to STANDARD_IA."
  type        = number
  default     = 90
}

variable "bronze_glacier_transition_days" {
  description = "Days after which current bronze objects transition to GLACIER"
  type        = number
  default     = 365
}

variable "bronze_noncurrent_expiration_days" {
  description = "Days after which noncurrent (overwritten) bronze object versions expire. Current versions never expire."
  type        = number
  default     = 90
}

variable "access_log_retention_days" {
  description = "Days after which S3 server access logs expire from the log bucket."
  type        = number
  default     = 365
}

variable "athena_results_expiration_days" {
  description = "Days after which Athena query results expire. Results are re-runnable scratch output."
  type        = number
  default     = 30
}
