data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
}

# --------------------------------------------------------------------------
# S3: private origin bucket. No website hosting - CloudFront reads objects
# via the REST endpoint using OAC + SigV4.
# --------------------------------------------------------------------------

resource "aws_s3_bucket" "site" {
  bucket = var.bucket_name
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket = aws_s3_bucket.site.id

  block_public_acls       = true
  block_public_policy      = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    object_ownership = "BucketOwnerEnforced" # ACLs off entirely
  }
}

# Bucket policy: GetObject only for the CloudFront service principal, and only
# when the request originates from THIS distribution (SourceArn condition).
# This is what keeps the bucket reachable exclusively through CloudFront.
data "aws_iam_policy_document" "bucket" {
  statement {
    sid     = "AllowCloudFrontOACRead"
    effect  = "Allow"
    actions = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.site.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.site.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id
  policy = data.aws_iam_policy_document.bucket.json

  # Ensure the public-access block is in place before we attach a policy, or
  # BlockPublicPolicy can reject it on a race.
  depends_on = [aws_s3_bucket_public_access_block.site]
}

# --------------------------------------------------------------------------
# CloudFront: OAC + distribution
# --------------------------------------------------------------------------

resource "aws_cloudfront_origin_access_control" "site" {
  name                              = "${var.bucket_name}-oac"
  description                       = "OAC for ${var.domain_name}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Explicit cache policy instead of the managed one, so the 5-minute TTL is
# visible and enforced regardless of what Cache-Control the origin sends.
#   min 0 / default 300 / max 300  ->  index.html caches for 300s, full stop.
# The origin also sets Cache-Control: public,max-age=300 (via the deploy
# workflow's --cache-control), so browsers respect the same window.
resource "aws_cloudfront_cache_policy" "five_min" {
  name        = "remedys-cart-5min"
  default_ttl = var.index_max_age
  min_ttl     = 0
  max_ttl     = var.index_max_age

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_brotli = true
    enable_accept_encoding_gzip   = true

    cookies_config {
      cookie_behavior = "none"
    }
    headers_config {
      header_behavior = "none"
    }
    query_strings_config {
      query_string_behavior = "none"
    }
  }
}

resource "aws_cloudfront_distribution" "site" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  comment             = "Remedy's Magic Cart - ${var.domain_name}"
  price_class         = "PriceClass_100" # US/Canada/Europe edges; cheapest, fine for a small US audience

  aliases = [var.domain_name]

  origin {
    origin_id                = "s3-${aws_s3_bucket.site.id}"
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-${aws_s3_bucket.site.id}"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    cache_policy_id        = aws_cloudfront_cache_policy.five_min.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # Reference the VALIDATION resource, not the cert directly. This forces
  # CloudFront to wait until the cert is actually issued before it will accept
  # it as an alternate-domain cert. See acm.tf for why this matters.
  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.site.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}
