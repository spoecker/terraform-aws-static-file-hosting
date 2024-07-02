terraform {

  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region                   = "ap-southeast-1"
  shared_config_files      = ["$HOME/.aws/config"]
  shared_credentials_files = ["$HOME/.aws/credentials"]
}

module "s3_source" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 4.0"

  bucket        = "s3-spoecker-terraform-source"
  force_destroy = true
}

module "cdn" {
  source              = "terraform-aws-modules/cloudfront/aws"
  comment             = "My awesome CloudFront"
  enabled             = true
  is_ipv6_enabled     = true
  price_class         = "PriceClass_All"
  retain_on_delete    = false
  wait_for_deployment = false

  create_origin_access_control = true
  origin_access_control = {
    s3_oac = {
      description      = "CloudFront access to S3"
      origin_type      = "s3"
      signing_behavior = "always"
      signing_protocol = "sigv4"
    }
  }

  origin = {

    s3_oac = { # with origin access control settings (recommended)
      domain_name           = module.s3_source.s3_bucket_bucket_regional_domain_name
      origin_access_control = "s3_oac" # key in `origin_access_control`
      #      origin_access_control_id = "E345SXM82MIOSU" # external OAС resource
    }
  }

  default_cache_behavior = {
    target_origin_id       = "s3_oac"
    viewer_protocol_policy = "allow-all"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]

    use_forwarded_values = false

    cache_policy_name            = "Managed-CachingOptimized"
    origin_request_policy_name   = "Managed-UserAgentRefererHeaders"
    response_headers_policy_name = "Managed-SimpleCORS"

  }
  geo_restriction = {
    restriction_type = "whitelist"
    locations        = ["TH"]
  }

  default_root_object = "index.html"

}

data "aws_iam_policy_document" "s3_policy" {
  # Origin Access Controls
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${module.s3_source.s3_bucket_arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [module.cdn.cloudfront_distribution_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "bucket_policy" {
  bucket = module.s3_source.s3_bucket_id
  policy = data.aws_iam_policy_document.s3_policy.json
}

# Next two are hacks that shouldnt be done, but its a shortcut to not have to build the full CI/CD Pipeline
resource "aws_s3_object" "file_upload" {
  bucket       = module.s3_source.s3_bucket_id
  key          = "index.html"
  source       = "index.html"
  source_hash  = filemd5("index.html")
  content_type = "text/html"

}

resource "null_resource" "deployment" {
   provisioner "local-exec" {
    command = "aws cloudfront create-invalidation --distribution-id ${module.cdn.cloudfront_distribution_id} --paths '/index.html'"
  }
  triggers = {
    always_run = timestamp()
  }
}