variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-southeast-1"
}

variable "s3_bucket_name" {
  description = "name of the S3 bucket (needs to be globally unique)"
  type        = string
  default     = "s3-spoecker-terraform-source"
}

variable "amplify_app_name" {
  description = "Name of the Amplify application"
  type        = string
  default     = "terraform-demo"
}