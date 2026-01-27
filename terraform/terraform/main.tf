terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "starttech-terraform-state"
    key            = "much-to-do/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "StartTech"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# Networking Module
module "networking" {
  source = "./modules/networking"

  environment        = var.environment
  vpc_cidr           = var.vpc_cidr
  availability_zones = data.aws_availability_zones.available.names
}

# Compute Module (ALB, ASG, EC2)
module "compute" {
  source = "./modules/compute"

  environment               = var.environment
  vpc_id                    = module.networking.vpc_id
  public_subnet_ids         = module.networking.public_subnet_ids
  private_subnet_ids        = module.networking.private_subnet_ids
  alb_security_group_id     = module.networking.alb_security_group_id
  backend_security_group_id = module.networking.backend_security_group_id
  instance_type             = var.instance_type
  asg_min_size              = var.asg_min_size
  asg_max_size              = var.asg_max_size
  asg_desired_capacity      = var.asg_desired_capacity
  docker_image              = var.docker_image
  log_group_name            = module.monitoring.backend_log_group

  depends_on = [module.networking]
}

# Storage Module (S3, CloudFront, ECR)
module "storage" {
  source = "./modules/storage"

  environment = var.environment

  depends_on = [module.networking]
}

# Monitoring Module (CloudWatch, ElastiCache, Alarms)
module "monitoring" {
  source = "./modules/monitoring"

  environment             = var.environment
  aws_region              = var.aws_region
  log_retention_days      = var.log_retention_days
  private_subnet_ids      = module.networking.private_subnet_ids
  redis_security_group_id = module.networking.redis_security_group_id
  redis_node_type         = var.redis_node_type
  redis_num_nodes         = var.redis_num_nodes
  redis_auth_token        = var.redis_auth_token
  target_group_name       = "much-to-do-backend-tg"

  depends_on = [module.networking]
}

# Get available AZs
data "aws_availability_zones" "available" {
  state = "available"
}
