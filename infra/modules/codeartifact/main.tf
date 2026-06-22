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
