variable "aws_region" {
  description = "Region for the S3 bucket and CloudFront control-plane calls. Not the cert region."
  type        = string
  default     = "us-west-2"
}

variable "domain_name" {
  description = "Fully-qualified custom domain served by CloudFront."
  type        = string
  default     = "posh.andytangpham.com"
}

variable "bucket_name" {
  description = "Globally-unique S3 bucket name. Arbitrary - it is NOT the website endpoint (OAC + private bucket), so it does not need to match the domain."
  type        = string
  default     = "posh-andytangpham-com-remedys-cart"
}

# ----- GitHub OIDC -----

variable "github_owner" {
  description = "GitHub org/user that owns the repo (the 'GH_USER' in your trust template)."
  type        = string
  # No default: set this. The trust policy is scoped to this exact value.
}

variable "github_repo" {
  description = "Repo name. Your local folder is 'remedy' but your OIDC template said 'remedys-cart'. Set this to the ACTUAL GitHub repo slug - the trust policy will silently fail auth if it's wrong."
  type        = string
  default     = "remedys-cart"
}

variable "github_branch" {
  description = "Branch allowed to assume the deploy role."
  type        = string
  default     = "main"
}

variable "create_oidc_provider" {
  description = "true = create the GitHub OIDC provider in this account. false = one already exists and we look it up. Having two providers for the same URL is an error, so flip to false if you've used GitHub OIDC before."
  type        = bool
  default     = true
}

variable "role_name" {
  description = "Name of the IAM role GitHub Actions assumes. Matches the workflow."
  type        = string
  default     = "github-deploy-remedys-cart"
}

variable "index_max_age" {
  description = "TTL in seconds for index.html at both CloudFront and the browser. 300 = push a fix mid-drop and clients pick it up within 5 min without an invalidation."
  type        = number
  default     = 300
}
