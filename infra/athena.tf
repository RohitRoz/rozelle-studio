# Dedicated Athena workgroup for the pipeline (never build on `primary`).
# Engine v3 is required for Iceberg MERGE (dbt incremental_strategy='merge').
# enforce_workgroup_configuration makes results location + encryption mandatory:
# clients cannot redirect output to an unencrypted bucket.

resource "aws_athena_workgroup" "pipeline" {
  name = "${var.project}-${var.environment}"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true
    bytes_scanned_cutoff_per_query     = var.athena_bytes_scanned_cutoff

    engine_version {
      selected_engine_version = "Athena engine version 3"
    }

    result_configuration {
      output_location = "s3://${module.athena_results.bucket_id}/"

      encryption_configuration {
        encryption_option = "SSE_KMS"
        kms_key_arn       = aws_kms_key.bronze.arn
      }
    }
  }

  tags = {
    Name = "${var.project}-${var.environment}"
  }
}
