#!/bin/bash
set -e

# Deploy Infrastructure Script
# Usage: ./deploy-infrastructure.sh [action] [environment]

ACTION=${1:-apply}
ENVIRONMENT=${2:-prod}
REGION=${AWS_REGION:-us-east-1}

echo "Starting infrastructure deployment"
echo "Action: $ACTION"
echo "Environment: $ENVIRONMENT"
echo "Region: $REGION"

# Navigate to terraform directory
cd terraform

# Initialize Terraform
echo "Initializing Terraform..."
terraform init

# Validate configuration
echo "Validating Terraform configuration..."
terraform validate

# Run linting checks
echo "Running TFLint..."
tflint || true

# Create tfvars file if not exists
if [ ! -f "terraform.tfvars" ]; then
  echo "Creating terraform.tfvars from example..."
  cp terraform.tfvars.example terraform.tfvars
  echo "Please update terraform.tfvars with your values"
  exit 1
fi

case $ACTION in
  plan)
    echo "Planning infrastructure changes..."
    terraform plan -out=tfplan
    echo "Plan saved to tfplan"
    ;;
  
  apply)
    echo "Applying infrastructure changes..."
    if [ -f "tfplan" ]; then
      terraform apply tfplan
    else
      terraform apply -auto-approve
    fi
    
    echo "Saving outputs..."
    terraform output -json > ../infrastructure-outputs.json
    
    echo "Infrastructure deployment completed"
    echo "Outputs saved to infrastructure-outputs.json"
    ;;
  
  destroy)
    echo "WARNING: This will destroy all infrastructure"
    read -p "Are you sure? (yes/no): " confirmation
    if [ "$confirmation" = "yes" ]; then
      terraform destroy -auto-approve
      echo "Infrastructure destroyed"
    else
      echo "Destroy cancelled"
    fi
    ;;
  
  output)
    echo "Current infrastructure outputs:"
    terraform output -json
    ;;
  
  *)
    echo "Unknown action: $ACTION"
    echo "Usage: $0 [plan|apply|destroy|output] [environment]"
    exit 1
    ;;
esac

echo "Done!"
