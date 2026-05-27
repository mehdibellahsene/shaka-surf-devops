terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }

  # State local par défaut (gitignoré). Pour un usage en équipe, migrer vers un
  # backend distant chiffré, par exemple :
  # backend "s3" {
  #   bucket         = "mon-bucket-tfstate"
  #   key            = "shaka-surf/terraform.tfstate"
  #   region         = "eu-west-3"
  #   dynamodb_table = "terraform-locks"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
    }
  }
}
