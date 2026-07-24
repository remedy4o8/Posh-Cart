# Remedy's Magic Cart — hosting

Static `index.html` (a Posh Peanut VIP-drop cart helper) served privately from
S3 through CloudFront at **https://posh.andytangpham.com**, deployed by GitHub
Actions over OIDC. Infrastructure is Terraform under [`infra/`](infra/).

## Layout

```
remedy/
├── index.html                    the app (fetches poshpeanut.com products.json client-side)
├── README.md
├── .github/workflows/deploy.yml  OIDC deploy on push to main
└── infra/                        Terraform (S3, OAC, CloudFront, ACM, Route53, IAM)
```

## Why S3 + CloudFront (and not Amplify)

You chose right for your stated goals. Amplify Hosting would be fewer steps —
it wraps S3 + CloudFront + CI behind one console flow — but it hides the bucket
policy, the OAC wiring, and the cert plumbing behind a managed abstraction you
don't control or easily audit. For a sysadmin who wants to read exactly what
was created and keep it in code, the explicit stack is the better call. The
cost is a bit more upfront wiring, which is what the Terraform absorbs. No
change recommended.

## What you fill in

Terraform derives your account ID automatically. Two values need your input:

- `github_owner` — the GitHub org/user (required, no default).
- `github_repo` — **confirm this.** Your local folder is `remedy`, but your
  OIDC template said `remedys-cart`. The trust policy is scoped to the exact
  repo slug; if it's wrong, the deploy job fails auth with nothing useful in
  the logs. Default is `remedys-cart` — change it if the real repo differs.

Copy `infra/terraform.tfvars.example` to `infra/terraform.tfvars` and set them.

## Preconditions I couldn't verify from here

I don't have access to your AWS account, so a couple of assumptions are baked
in and fail *loudly* (not silently) if wrong:

- **`andytangpham.com` is a hosted zone in Route 53 in this same account.** The
  `aws_route53_zone` data lookup errors on `plan` if it isn't — the safe
  outcome you asked for. If the domain's DNS is hosted elsewhere, the setup
  differs (you'd validate the cert and publish the alias wherever DNS lives),
  so stop and tell me before proceeding.
- **The default bucket name is free.** `posh-andytangpham-com-remedys-cart` is
  unusual enough to be available, but S3 names are global; change it if apply
  complains.
- **No existing GitHub OIDC provider.** If you've used GitHub OIDC in this
  account before, one already exists and creating a second is an error — set
  `create_oidc_provider = false`.

## Deploy order

The bootstrap (Terraform) runs once with your own admin credentials. The OIDC
role is only for *ongoing* deploys — it deliberately can't create
infrastructure.

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars   # then edit
terraform init
terraform apply
```

**`apply` will pause for a few minutes on `aws_acm_certificate_validation`.**
That's the non-obvious bit worth stating plainly: CloudFront won't accept an
alternate-domain cert until ACM has *issued* it, and issuance waits on the
DNS-validation CNAME propagating. Terraform writes that CNAME into your zone
automatically and then blocks until ACM confirms. It looks like a hang; it
isn't. The distribution is created only after the cert is live, so the domain
config is right the first time — no slow second update to attach the cert
later.

After apply, wire the workflow with the outputs:

```bash
terraform output          # bucket_name, distribution_id, deploy_role_arn, ...
```

Put those into `.github/workflows/deploy.yml` (`env:` block: `ROLE_ARN`,
`BUCKET`, `DIST_ID` — the ARN needs your account ID).

Seed the first object so the site answers immediately (CI does this on every
later push):

```bash
aws s3 cp ../index.html s3://<bucket_name>/index.html \
  --cache-control "public,max-age=300"
```

Then push to `main` and CI takes over.

## Cache behavior

- `index.html`: `Cache-Control: public,max-age=300`, set by the deploy sync and
  enforced by a custom CloudFront cache policy (`min 0 / default 300 / max
  300`). So the 5-minute window holds at the edge *and* in browsers regardless
  of header drift. The relevant non-obvious point: CloudFront's default 1-day
  TTL only applies when the origin sends **no** `Cache-Control`; since the sync
  always sets one, and the policy caps `max_ttl` at 300 anyway, there's no path
  to a stale-for-a-day copy. Push a fix mid-drop, clients pick it up within 5
  min.
- The product fetch (`poshpeanut.com/.../products.json?...&t=<timestamp>`)
  never touches CloudFront at all — it's a cross-origin call straight from the
  browser to Shopify, and the `t=` param busts Shopify's + the browser's cache
  every refresh. CloudFront isn't in that path, so there's nothing to configure
  and nothing to accidentally cache. Working as intended.

## Verification

Replace `<dist>.cloudfront.net` / `<bucket>` with your outputs.

```bash
# 1. CloudFront serves index with the 5-min header
curl -I https://<dist>.cloudfront.net
#    expect: HTTP/2 200 ; cache-control: public,max-age=300

# 2. Bucket is NOT publicly readable
curl -I https://<bucket>.s3.us-west-2.amazonaws.com/index.html
#    expect: HTTP/1.1 403 Forbidden

# 3. Custom domain over valid TLS  (after DNS propagates)
curl -I https://posh.andytangpham.com
#    expect: HTTP/2 200
curl -vI https://posh.andytangpham.com 2>&1 | grep -i "subject\|issuer\|SSL cert"

# 4. DNS resolves to CloudFront
dig +short posh.andytangpham.com

# 5. HTTP redirects to HTTPS
curl -sI http://posh.andytangpham.com | grep -i "location\|^HTTP"
#    expect: 301/302 -> https://

# 6. Push test: edit index.html, commit to main, confirm the change is live
#    within 5 minutes (Actions run + invalidation).

# 7. Open https://posh.andytangpham.com in devtools, confirm the products.json
#    fetch succeeds with no CORS errors in console.
```

## Estimated monthly cost

Effectively the price of the hosted zone you already pay for.

| Item | Cost |
|---|---|
| Route 53 hosted zone | $0.50 / mo (already incurred; not new) |
| Route 53 queries | ~$0.00 (pennies per million) |
| S3 storage + requests | < $0.01 (a few KB, tiny traffic) |
| CloudFront | $0.00 — a small audience sits inside the always-free tier (1 TB out, 10M requests/mo) |
| ACM certificate | free |

**New marginal cost of this stack: ~$0.00–$0.01/month.** If the drop somehow
drew serious traffic, CloudFront past the free tier is ~$0.085/GB out in North
America — still cents for anything short of thousands of visitors.

## Security notes

- Bucket has all four public-access blocks on, ACLs disabled
  (`BucketOwnerEnforced`), and a policy granting `s3:GetObject` only to the
  CloudFront service principal conditioned on this distribution's ARN. Reachable
  only through CloudFront.
- No long-lived AWS keys anywhere. GitHub authenticates via OIDC; the role
  trust is scoped to `repo:<owner>/<repo>:ref:refs/heads/main`, and its
  permissions are exactly `s3:ListBucket` (bucket), `s3:PutObject`/`DeleteObject`
  (objects), `cloudfront:CreateInvalidation` (this distribution) — no wildcards
  on resources.
