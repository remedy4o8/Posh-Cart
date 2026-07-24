# A/AAAA alias records pointing the custom domain at CloudFront.
# Alias (not CNAME): free, resolves at the zone apex or subdomain, and lets
# Route 53 answer with CloudFront's current edge IPs directly.
# Z2FDTNDATAQYW2 is CloudFront's fixed, global hosted-zone ID - same for every
# distribution, not a typo.

resource "aws_route53_record" "a" {
  zone_id = aws_route53_zone.posh.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.site.domain_name
    zone_id                = "Z2FDTNDATAQYW2"
    evaluate_target_health = false
  }
}

# IPv6. The distribution has is_ipv6_enabled = true, so publish AAAA too.
resource "aws_route53_record" "aaaa" {
  zone_id = aws_route53_zone.posh.zone_id
  name    = var.domain_name
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.site.domain_name
    zone_id                = "Z2FDTNDATAQYW2"
    evaluate_target_health = false
  }
}
