# Glue Data Catalog: the metastore. Terraform owns the namespaces (databases,
# with location_uri pinned to the lakehouse bucket); dbt/Athena own the tables
# created inside them at runtime.

locals {
  # Glue/Athena names must be lowercase + underscores.
  glue_db_prefix = replace("${var.project}_${var.environment}", "-", "_")

  # One database per dbt layer; location keeps each layer under its own S3 prefix.
  glue_databases = toset(["staging", "intermediate", "marts"])
}

resource "aws_glue_catalog_database" "layers" {
  for_each = local.glue_databases

  name         = "${local.glue_db_prefix}_${each.key}"
  description  = "${var.project} ${each.key} layer (dbt-managed tables)"
  location_uri = "s3://${module.lakehouse.bucket_id}/${each.key}/"
}

# Account+region-wide singleton: encrypts catalog metadata (table definitions,
# schemas, S3 locations) with the project CMK.
resource "aws_glue_data_catalog_encryption_settings" "this" {
  data_catalog_encryption_settings {
    encryption_at_rest {
      catalog_encryption_mode = "SSE-KMS"
      sse_aws_kms_key_id      = aws_kms_key.bronze.arn
    }

    connection_password_encryption {
      return_connection_password_encrypted = true
      aws_kms_key_id                       = aws_kms_key.bronze.arn
    }
  }
}
