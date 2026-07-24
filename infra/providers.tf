terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
  }

  # Local state is fine for a one-off personal project. If you'd rather keep
  # state in S3, uncomment and point at a bucket you already own. Do NOT use
  # the same bucket this stack creates.
  #
  # backend "s3" {
  #   bucket = "your-tfstate-bucket"
  #   key    = "remedys-cart/terraform.tfstate"
  #   region = "us-west-2"
  # }
}

# Primary provider: everything except the ACM cert lives here.
provider "aws" {
  region = var.aws_region
}

# CloudFront only reads certificates from us-east-1, regardless of where the
# bucket or distribution "live". This aliased provider exists solely to issue
# the ACM cert in that region. This is the classic time-waster, so it's called
# out explicitly.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}
