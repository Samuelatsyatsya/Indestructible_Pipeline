resource "aws_codeartifact_domain" "this" {
  domain = var.domain_name
  tags   = var.tags
}

resource "aws_codeartifact_repository" "npm_upstream" {
  repository  = "npm-upstream-proxy"
  domain      = aws_codeartifact_domain.this.domain
  description = "Upstream proxy for public npm registry"

  external_connections {
    external_connection_name = "public:npmjs"
  }

  tags = var.tags
}

resource "aws_codeartifact_repository" "npm" {
  repository  = var.npm_repo_name
  domain      = aws_codeartifact_domain.this.domain
  description = "FinCorp npm repository — proxies through public npmjs"

  upstream {
    repository_name = aws_codeartifact_repository.npm_upstream.repository
  }

  tags = var.tags
}

# ── CI access ────────────────────────────────────────────────────────────────
# The Jenkins pipeline (CodeArtifact Login stage) needs to mint a short-lived npm
# token and read packages. Scoped to this domain/repo where possible;
# sts:GetServiceBearerToken must be "*" but is fenced to CodeArtifact via condition.
data "aws_iam_policy_document" "ci_pull" {
  statement {
    sid       = "GetAuthToken"
    effect    = "Allow"
    actions   = ["codeartifact:GetAuthorizationToken"]
    resources = [aws_codeartifact_domain.this.arn]
  }

  statement {
    sid    = "ReadRepository"
    effect = "Allow"
    actions = [
      "codeartifact:GetRepositoryEndpoint",
      "codeartifact:ReadFromRepository",
    ]
    resources = [aws_codeartifact_repository.npm.arn]
  }

  statement {
    sid       = "ServiceBearerToken"
    effect    = "Allow"
    actions   = ["sts:GetServiceBearerToken"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "sts:AWSServiceName"
      values   = ["codeartifact.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "ci_pull" {
  name        = "${var.domain_name}-codeartifact-ci-pull"
  description = "Allows the CI principal to fetch a CodeArtifact npm token and read packages"
  policy      = data.aws_iam_policy_document.ci_pull.json
  tags        = var.tags
}

resource "aws_iam_user_policy_attachment" "ci_pull" {
  user       = var.ci_principal_name
  policy_arn = aws_iam_policy.ci_pull.arn
}
