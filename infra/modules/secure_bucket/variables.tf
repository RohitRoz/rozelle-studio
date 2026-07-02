variable "name" {
  description = "Full bucket name."
  type        = string
}

variable "layer" {
  description = "Layer tag value (e.g. bronze, lakehouse, athena-results)."
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the CMK used for default encryption and enforced by the bucket policy."
  type        = string
}

variable "transitions" {
  description = "Storage-class transitions for current objects. Leave empty for buckets that must not tier (Iceberg)."
  type = list(object({
    days          = number
    storage_class = string
  }))
  default = []
}

variable "expiration_days" {
  description = "Days after which current objects expire. null = never (data buckets)."
  type        = number
  default     = null
}

variable "noncurrent_expiration_days" {
  description = "Days after which noncurrent object versions expire. null = never."
  type        = number
  default     = null
}
