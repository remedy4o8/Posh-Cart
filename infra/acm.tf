# --------------------------------------------------------------------------
# ACM certificate. MUST be in us-east-1 (see providers.tf) because CloudFront
# only reads certs from that region. DNS validation, not email.
#
# Sequencing (this is the part that surprises people):
#   1. aws_acm_certificate         - REQUESTS the cert (status: pending)
#   2. aws_route53_record          - writes the validation CNAME into the zone
#   3. aws_acm_certificate_validation - BLOCKS until ACM sees the CNAME and
#                                       flips the cert to ISSUED
#   4. Only then does the CloudFront distribution (which references the
#      validation resource) get created/updated with the cert attached.
# Terraform apply will pause on step 3 for a few minutes. That's expected,
# not a hang.
# --------------------------------------------------------------------------

resource "aws_acm_certificate" "site" {
  provider          = aws.us_east_1
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# Subdomain delegation. andytangpham.com stays on GoDaddy; we create a Route 53
# hosted zone for JUST posh.andytangpham.com. You then add ONE NS record for
# "posh" at GoDaddy pointing to this zone's four nameservers (output:
# route53_name_servers). Nothing else on the parent domain is touched.
#
# Because this zone is only reachable publicly once GoDaddy delegation is in
# place, apply in two phases (see README): create the zone first, add the NS
# record at GoDaddy, then apply the rest so ACM validation can resolve.
resource "aws_route53_zone" "posh" {
  name = var.domain_name
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.site.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id         = aws_route53_zone.posh.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "site" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.site.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}
