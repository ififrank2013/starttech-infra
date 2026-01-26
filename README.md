# StartTech Infrastructure Repository

This repository contains all Infrastructure as Code (IaC) and deployment automation for the StartTech application. It provides production-grade infrastructure on AWS with comprehensive monitoring and observability.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Repository Structure](#repository-structure)
- [Terraform Modules](#terraform-modules)
- [Deployment](#deployment)
- [Monitoring](#monitoring)
- [Troubleshooting](#troubleshooting)

## Overview

This infrastructure-as-code repository enables:

- **Multi-tier AWS deployment** with auto-scaling and load balancing
- **High availability** across 2+ availability zones
- **Container orchestration** via ECR and ECS/EC2
- **Database and caching** with managed services
- **Comprehensive monitoring** with CloudWatch integration
- **CI/CD integration** via GitHub Actions
- **Infrastructure automation** with Terraform

### Key Features

✅ Modular Terraform design for reusability  
✅ Multi-AZ deployment for fault tolerance  
✅ Auto-scaling based on CPU utilization  
✅ CloudWatch dashboards and alarms  
✅ Security groups and IAM roles  
✅ CloudFront CDN for static assets  
✅ Automated health checks  
✅ Zero-downtime deployments  

## Architecture

### Infrastructure Stack

```
┌─────────────────────────────────────────────────────┐
│                    CloudFront (CDN)                 │
│            Static Assets + Caching Layer            │
└──────────────────────────┬──────────────────────────┘
                           │
        ┌──────────────────┴──────────────────┐
        │    Application Load Balancer       │
        │    (Multi-AZ, Health Checks)       │
        └──────────────────┬──────────────────┘
                           │
        ┌──────────────────┴──────────────────┐
        │   Auto Scaling Group (ASG)         │
        │   EC2 Instances (API Servers)      │
        └──────────────────┬──────────────────┘
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
   ┌────▼─────┐    ┌──────▼──────┐   ┌──────▼──────┐
   │ RDS/DB   │    │ ElastiCache │   │  S3 Buckets │
   │(MongoDB) │    │   (Redis)   │   │  (Storage)  │
   └──────────┘    └─────────────┘   └─────────────┘

┌─────────────────────────────────────────────────────┐
│          CloudWatch Monitoring & Logging            │
│  (Metrics, Logs, Dashboards, Alarms, Insights)    │
└─────────────────────────────────────────────────────┘
```

### AWS Services

| Service | Purpose | Configuration |
|---------|---------|----------------|
| **VPC** | Networking | 2 public + 2 private subnets |
| **EC2** | Compute | t3.medium instances in ASG |
| **ALB** | Load Balancing | HTTP/HTTPS with health checks |
| **ASG** | Auto-Scaling | CPU-based (30%-70%) |
| **ECR** | Container Registry | Private registry for backend |
| **S3** | Object Storage | Frontend assets + backups |
| **CloudFront** | CDN | Static content distribution |
| **RDS/MongoDB** | Database | Managed data storage |
| **ElastiCache** | Caching | Redis for sessions/cache |
| **CloudWatch** | Monitoring | Logs, metrics, dashboards, alarms |
| **IAM** | Access Control | Role-based permissions |

## Prerequisites

### Required Tools

- **Terraform** >= v1.0 (Install from [terraform.io](https://www.terraform.io/downloads))
- **AWS CLI** >= v2 (Install from [aws.amazon.com](https://aws.amazon.com/cli/))
- **Git** >= v2.0
- **Bash** (Linux/Mac) or PowerShell (Windows)

### AWS Requirements

- AWS Account with appropriate IAM permissions
- AWS Access Key ID and Secret Access Key
- Region configured (default: us-east-1)

### Optional Tools

- **Terraform Cloud** account (for remote state)
- **AWS SSO** configured (for CLI authentication)
- **Docker** (for ECR image building)

## Quick Start

### 1. Setup AWS Credentials

```bash
# Configure AWS CLI
aws configure

# Or use AWS SSO
aws sso login --profile your-profile

# Or export credentials
export AWS_ACCESS_KEY_ID=your_access_key
export AWS_SECRET_ACCESS_KEY=your_secret_key
export AWS_DEFAULT_REGION=us-east-1
```

### 2. Initialize Terraform

```bash
cd terraform
terraform init
```

### 3. Review Infrastructure Plan

```bash
terraform plan -out=tfplan
```

### 4. Deploy Infrastructure

```bash
terraform apply tfplan
```

### 5. Verify Deployment

```bash
terraform output

# Or check via AWS Console
aws ec2 describe-instances --region us-east-1
aws elbv2 describe-load-balancers --region us-east-1
```

## Repository Structure

```
starttech-infra/
├── .github/
│   └── workflows/
│       └── infrastructure-deploy.yml    # GitHub Actions workflow
├── terraform/
│   ├── main.tf                          # Root configuration
│   ├── variables.tf                     # Input variables
│   ├── outputs.tf                       # Output values
│   ├── terraform.tfvars.example         # Example variables
│   ├── modules/
│   │   ├── networking/
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   ├── compute/
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   ├── storage/
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   └── monitoring/
│   │       ├── main.tf
│   │       ├── variables.tf
│   │       └── outputs.tf
│   └── .terraform.lock.hcl             # Locked dependency versions
├── scripts/
│   └── deploy-infrastructure.sh         # Deployment automation script
├── monitoring/
│   ├── cloudwatch-dashboard.json       # Dashboard configuration
│   ├── alarm-definitions.json          # CloudWatch alarms
│   └── log-insights-queries.txt        # Pre-built queries
├── README.md                            # This file
└── .gitignore                           # Git ignore rules

```

## Terraform Modules

### Networking Module (`modules/networking`)

Manages VPC, subnets, and network configuration.

**Variables:**
- `vpc_cidr`: VPC CIDR block (default: 10.0.0.0/16)
- `availability_zones`: Number of AZs (default: 2)

**Outputs:**
- `vpc_id`: VPC ID
- `public_subnet_ids`: Public subnet IDs
- `private_subnet_ids`: Private subnet IDs
- `security_group_id`: Security group ID

### Compute Module (`modules/compute`)

Manages EC2, ALB, and Auto Scaling.

**Variables:**
- `instance_type`: EC2 instance type (default: t3.medium)
- `desired_capacity`: ASG desired count (default: 2)
- `min_size`: ASG minimum (default: 1)
- `max_size`: ASG maximum (default: 4)

**Outputs:**
- `alb_dns_name`: ALB endpoint
- `asg_name`: Auto Scaling Group name
- `instance_profile_arn`: IAM instance profile

### Storage Module (`modules/storage`)

Manages S3, ECR, and RDS.

**Variables:**
- `s3_bucket_name`: S3 bucket name
- `ecr_repo_name`: ECR repository name
- `db_instance_class`: Database instance type

**Outputs:**
- `s3_bucket_url`: S3 bucket URL
- `ecr_repository_url`: ECR repository URL
- `db_endpoint`: Database endpoint

### Monitoring Module (`modules/monitoring`)

Manages CloudWatch resources.

**Variables:**
- `log_retention_days`: Log retention period (default: 7)
- `alarm_email`: SNS notification email

**Outputs:**
- `log_group_names`: CloudWatch log groups
- `dashboard_url`: CloudWatch dashboard URL

## Deployment

### Automated Deployment via GitHub Actions

The repository includes automated deployment via GitHub Actions. Trigger deployment by:

1. **Push to main branch** (automatic deployment)
2. **Manual workflow dispatch** (GitHub UI)
3. **Tag release** (version-based deployment)

See [`.github/workflows/infrastructure-deploy.yml`](.github/workflows/infrastructure-deploy.yml) for details.

### Manual Deployment

#### Plan

```bash
cd terraform
terraform plan -var-file=terraform.tfvars -out=tfplan
```

#### Apply

```bash
terraform apply tfplan
```

#### Destroy

```bash
terraform destroy -var-file=terraform.tfvars
```

### Using Deploy Script

```bash
# Plan infrastructure
./scripts/deploy-infrastructure.sh plan

# Apply infrastructure
./scripts/deploy-infrastructure.sh apply

# Destroy infrastructure
./scripts/deploy-infrastructure.sh destroy

# Get outputs
./scripts/deploy-infrastructure.sh output
```

## Monitoring

### CloudWatch Dashboard

The deployment automatically creates a CloudWatch dashboard with:

- **EC2 Metrics**: CPU utilization, network I/O
- **ALB Metrics**: Request count, latency, target health
- **Cache Metrics**: Hit/miss rates, evictions
- **Application Logs**: Error patterns, performance
- **Custom Metrics**: Business KPIs

**Access Dashboard:**
```bash
aws cloudwatch get-dashboard --dashboard-name StartTechDashboard
```

### CloudWatch Alarms

Pre-configured alarms for:

| Alarm | Threshold | Action |
|-------|-----------|--------|
| High CPU | > 70% (2 periods) | Auto-scale up |
| Low CPU | < 30% (2 periods) | Auto-scale down |
| Unhealthy Targets | ≥ 1 | Notify SNS topic |
| High Latency | > 1000ms | Notify SNS topic |
| Redis Evictions | > 0 | Notify SNS topic |
| High Memory | > 85% | Notify SNS topic |
| 5XX Errors | > 10 | Notify SNS topic |
| Disk Space | > 80% | Notify SNS topic |

### CloudWatch Logs Insights

Pre-built queries available in [`monitoring/log-insights-queries.txt`](monitoring/log-insights-queries.txt):

- Error analysis
- Performance metrics
- Application health
- Deployment tracking
- Security analysis
- Infrastructure metrics
- Business analytics
- Debugging utilities

**Example Query:**
```
fields @timestamp, @duration, status_code
| filter status_code >= 400
| stats count() as error_count by bin(5m)
```

## Troubleshooting

### Terraform State Issues

```bash
# Show current state
terraform state list

# Show specific resource
terraform state show module.compute.aws_instance.web

# Refresh state
terraform refresh
```

### Deployment Failures

```bash
# Check Terraform logs
export TF_LOG=DEBUG
terraform plan

# Validate configuration
terraform validate

# Check syntax
terraform fmt -check -recursive
```

### AWS Connectivity Issues

```bash
# Verify AWS credentials
aws sts get-caller-identity

# Check region
aws ec2 describe-regions --region-names us-east-1

# List resources
aws ec2 describe-instances --region us-east-1
```

### Instance Connection Issues

```bash
# Check security groups
aws ec2 describe-security-groups --region us-east-1

# Check ALB health
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:...

# SSH into instance (if needed)
ssh -i key.pem ec2-user@instance-ip
```

### Monitoring Gaps

```bash
# Check log groups
aws logs describe-log-groups --region us-east-1

# Check CloudWatch alarms
aws cloudwatch describe-alarms --region us-east-1

# View dashboard
aws cloudwatch get-dashboard --dashboard-name StartTechDashboard
```

## Variables Configuration

Create `terraform.tfvars` from `terraform.tfvars.example`:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Edit the file with your values:

```hcl
aws_region              = "us-east-1"
environment             = "production"
vpc_cidr                = "10.0.0.0/16"
instance_type           = "t3.medium"
desired_capacity        = 2
min_size                = 1
max_size                = 4
rds_instance_class      = "db.t3.micro"
mongodb_instance_class  = "db.t3.micro"
redis_instance_type     = "cache.t3.micro"
log_retention_days      = 7
alarm_email             = "ops@starttech.com"
```

## Security Considerations

- **State File**: Store Terraform state remotely in S3 with encryption
- **Access Control**: Use IAM roles and policies for least privilege
- **Network**: Use security groups to restrict traffic
- **Secrets**: Never commit credentials; use AWS Secrets Manager
- **Logging**: Enable CloudTrail and CloudWatch Logs
- **Encryption**: Enable encryption at rest and in transit


## Additional Resources

- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS Architecture Guide](https://docs.aws.amazon.com/architecture/)
- [Terraform Best Practices](https://www.terraform.io/docs/cloud/guides/recommended-practices/index.html)
- [CloudWatch Documentation](https://docs.aws.amazon.com/cloudwatch/)

## Support

For issues or questions:
1. Check the Troubleshooting section above
2. Review CloudWatch logs and metrics
3. Check Terraform state and plan output
4. Create an issue in the repository

---

**Last Updated**: 2026  
**Terraform Version**: 1.0+  
**AWS Region**: us-east-1 (configurable)

# Workflow retry Tue Jan 27 00:25:25 WAT 2026
