# ============================================================================
# provider.tf — Configuration du provider AWS
# ============================================================================
# Ce fichier configure la connexion entre Terraform et AWS.
# Terraform a besoin de savoir :
#   - Quel provider utiliser (ici AWS)
#   - Dans quelle région déployer les ressources
#   - Comment s'authentifier (via les variables ou le fichier ~/.aws/credentials)
# ============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region     = var.aws_region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key

  default_tags {
    tags = {
      Project     = "terraform-flask-deployment"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
