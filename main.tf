terraform {

  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }

  required_version = ">= 1.2.0"
}

# Configuring the AWS provider to use the default CLI profile
provider "aws" {
  region                   = var.aws_region
  shared_config_files      = ["$HOME/.aws/config"]
  shared_credentials_files = ["$HOME/.aws/credentials"]
}

# Creating a S3 bucket that is going to store the data for CloudFront
module "s3_source" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 4.0"

  bucket        = var.s3_bucket_name
  force_destroy = true
}

# Creating a CloudFront distribution with the S3 bucket as the source and using OAC (Origin Access Control to access the data in the S3 bucket)
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
      origin_access_control = "s3_oac" 

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
    locations        = ["TH"] #Only allowing TH access at the moment
  }

  default_root_object = "index.html"

}

# Need to make sure that the CloudFront OAC can access the S3 bucket
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

# Next two are hacks that shouldnt be done, but its a shortcut to not have to build the full CI/CD Pipeline (Normally would probably create CodePipeline to deploy the content to S3 and then make the API call for the invalidation.)
resource "aws_s3_object" "file_upload" {
  bucket       = module.s3_source.s3_bucket_id
  key          = "index.html"
  source       = "WebsiteCode/index.html"
  source_hash  = filemd5("WebsiteCode/index.html")
  content_type = "text/html"

}

resource "null_resource" "deployment" {
  provisioner "local-exec" {
    command = "aws cloudfront create-invalidation --distribution-id ${module.cdn.cloudfront_distribution_id} --paths '/index.html'"
  }
  triggers = {
    always_run = filemd5("WebsiteCode/index.html") #timestamp()
  }
}


# Second hosting option is Amplify App (Normally amplify would also be connected to a source code repo, because of time reasons I am using here a terraform module that runs a lambda if an archive in S3 is updated.)

module "s3_amplify_source" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 4.0"

  bucket        = "${var.s3_bucket_name}-amplify"
  force_destroy = true
}

resource "aws_amplify_app" "example" {
  name = var.amplify_app_name
}

resource "aws_amplify_branch" "site" {
  app_id      = aws_amplify_app.example.id
  branch_name = "main"
  stage       = "PRODUCTION"

}

module "aws_amplify_static_website_from_s3" {
  source = "./modules/terraform-aws-amplify-static-website-deployment-from-s3"

  aws_s3_bucket_store = {
    bucket_name   = module.s3_amplify_source.s3_bucket_id
    bucket_path   = "test"
    zip_file_name = "artifact.zip"
    region        = var.aws_region
  }
  aws_amplify_app = {
    id              = aws_amplify_app.example.id
    deployment_name = aws_amplify_branch.site.branch_name
  }
}

#Amplify Deployment (Creating new zip and uploading it to S3)

data "archive_file" "amplify-source" {
  type        = "zip"
  source_dir  = "WebsiteCode/"
  output_path = "artifacts/artifact.zip"
}

resource "aws_s3_object" "amplify-file_upload" {
  bucket       = module.s3_amplify_source.s3_bucket_id
  key          = "test/artifact.zip"
  source       = data.archive_file.amplify-source.output_path
  source_hash  = filemd5(data.archive_file.amplify-source.output_path)
  content_type = "application/zip"

}