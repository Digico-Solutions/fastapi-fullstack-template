# =============================================================================
# GitHub Actions OIDC Authentication for ECR
# =============================================================================
# This module creates the IAM resources needed for GitHub Actions to 
# authenticate with AWS using OIDC and push Docker images to ECR.
# =============================================================================

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 3.0"
    }
  }
}

# =============================================================================
# Variables
# =============================================================================

variable "aws_region" {
  description = "AWS region for the provider"
  type        = string
}

variable "github_org" {
  description = "GitHub organization name"
  type        = string
  validation {
    condition     = length(var.github_org) > 0
    error_message = "GitHub organization name cannot be empty."
  }
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
  validation {
    condition     = length(var.github_repo) > 0
    error_message = "GitHub repository name cannot be empty."
  }
}

variable "ecr_repository_backend" {
  description = "Name of the ECR repository for backend images"
  type        = string
  validation {
    condition     = length(var.ecr_repository_backend) > 0
    error_message = "Backend ECR repository name cannot be empty."
  }
}

variable "ecr_repository_frontend" {
  description = "Name of the ECR repository for frontend images"
  type        = string
  validation {
    condition     = length(var.ecr_repository_frontend) > 0
    error_message = "Frontend ECR repository name cannot be empty."
  }
}

variable "role_name" {
  description = "Name of the IAM role for GitHub Actions"
  type        = string
  default     = "github-actions-ecr-role"
}

# =============================================================================
# Provider
# =============================================================================

provider "aws" {
  region = var.aws_region
}

# =============================================================================
# Data Sources
# =============================================================================

data "aws_caller_identity" "current" {}

# Get GitHub OIDC thumbprint
data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

# =============================================================================
# OIDC Provider
# =============================================================================

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]

  tags = {
    Name      = "github-actions-oidc"
    ManagedBy = "terraform"
  }
}

# =============================================================================
# IAM Role with Trust Policy
# =============================================================================

data "aws_iam_policy_document" "github_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${var.github_repo}:*"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = var.role_name
  assume_role_policy = data.aws_iam_policy_document.github_assume_role.json

  tags = {
    Name      = var.role_name
    ManagedBy = "terraform"
  }
}

# =============================================================================
# ECR Push Policy
# =============================================================================

data "aws_iam_policy_document" "ecr_push" {
  # GetAuthorizationToken must have resource "*"
  statement {
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken"
    ]
    resources = ["*"]
  }

  # Repository-specific permissions for backend and frontend
  statement {
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage"
    ]
    resources = [
      "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/${var.ecr_repository_backend}",
      "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/${var.ecr_repository_frontend}"
    ]
  }
}

resource "aws_iam_role_policy" "ecr_push" {
  name   = "ecr-push-policy"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.ecr_push.json
}

# =============================================================================
# Outputs
# =============================================================================

output "role_arn" {
  description = "ARN of the IAM role for GitHub Actions (add to GitHub Secrets as AWS_ROLE_ARN)"
  value       = aws_iam_role.github_actions.arn
}

output "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider"
  value       = aws_iam_openid_connect_provider.github.arn
}
