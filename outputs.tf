output "cloudfront_distribution_domain_name" {
  description = "The domain name corresponding to the distribution."
  value       = module.cdn.cloudfront_distribution_domain_name
}

output "amplify_domain_name" {
  description = "The Amplify domain name:"
  value       = "https://${aws_amplify_app.example.production_branch[0].branch_name}.${aws_amplify_app.example.default_domain}"
}