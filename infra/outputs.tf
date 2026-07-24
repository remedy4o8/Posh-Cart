# These map 1:1 onto the placeholders in .github/workflows/deploy.yml and the
# verification commands in the README.

output "bucket_name" {
  description = "S3 bucket -> workflow's s3://BUCKET"
  value       = aws_s3_bucket.site.id
}

output "distribution_id" {
  description = "CloudFront distribution -> workflow's DIST_ID"
  value       = aws_cloudfront_distribution.site.id
}

output "distribution_domain_name" {
  description = "*.cloudfront.net domain, for the pre-DNS curl check"
  value       = aws_cloudfront_distribution.site.domain_name
}

output "deploy_role_arn" {
  description = "IAM role ARN -> workflow's role-to-assume"
  value       = aws_iam_role.deploy.arn
}

output "certificate_arn" {
  description = "ACM cert ARN (us-east-1)"
  value       = aws_acm_certificate.site.arn
}

output "custom_domain_url" {
  value = "https://${var.domain_name}"
}

output "route53_name_servers" {
  description = "Delegate the subdomain: at GoDaddy add an NS record, host 'posh', pointing to these four nameservers."
  value       = aws_route53_zone.posh.name_servers
}
