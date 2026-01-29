### CloudFront Provider Inconsistency Error

**Error Message:**
```
Error: Provider produced inconsistent final plan
When expanding the plan for module.storage.aws_cloudfront_distribution.frontend to include new values
learned so far during apply, provider "registry.terraform.io/hashicorp/aws"
produced an invalid new value for .origin...
```

**Cause:**
- CloudFront origins are defined as an unordered SET in Terraform
- When S3 bucket domain becomes `(known after apply)` during recreation, Terraform can't compute the set hash
- Provider can't validate the planned change because one origin domain is unknown
- This typically happens when the S3 bucket is being destroyed and recreated simultaneously with CloudFront update

**Root Cause Analysis:**
1. S3 bucket was using `bucket = "${var.environment}-frontend-${data.aws_caller_identity.current.account_id}"`
2. The `data.aws_caller_identity.current` reference added unnecessary computation
3. This caused Terraform to mark the bucket for recreation on minor state changes
4. CloudFront tried to update its origins while S3 domain was unknown
5. Provider set comparison failed due to unknown S3 origin domain hash

**Solution (Applied):**

**1. Fixed S3 Bucket Naming:**
```hcl
resource "aws_s3_bucket" "frontend" {
  bucket = "${var.environment}-frontend"  # Fixed name, no account ID
  # Removed force_destroy to prevent unnecessary recreation
  tags = {
    Name = "${var.environment}-frontend"
  }
}
```

**2. Reordered CloudFront Origins:**
```hcl
resource "aws_cloudfront_distribution" "frontend" {
  # ALB Origin FIRST (more stable, doesn't depend on S3 recreation)
  origin {
    domain_name = var.alb_dns_name != "" ? var.alb_dns_name : "placeholder.example.com"
    origin_id   = "alb-backend"
    # ... custom_origin_config
  }
  
  # S3 Origin SECOND (depends on bucket, but now stable)
  origin {
    domain_name = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id   = "myS3Origin"
    # ... s3_origin_config
  }
}
```

**3. Added Explicit Dependencies:**
```hcl
depends_on = [
  aws_s3_bucket.frontend,
  aws_s3_bucket_policy.frontend,
  aws_s3_bucket_website_configuration.frontend
]
```

**If Error Still Occurs:**

1. **Manually separate the updates:**
```bash
# Step 1: Apply only S3 changes
terraform apply -target=module.storage.aws_s3_bucket.frontend \
  -target=module.storage.aws_s3_bucket_policy.frontend \
  -target=module.storage.aws_s3_bucket_website_configuration.frontend

# Step 2: Refresh state
terraform refresh

# Step 3: Apply CloudFront changes
terraform apply -target=module.storage.aws_cloudfront_distribution.frontend

# Step 4: Full apply to ensure consistency
terraform apply
```

2. **Recreate state file if necessary:**
```bash
# Backup current state
cp terraform.tfstate terraform.tfstate.backup

# Remove CloudFront from state temporarily
terraform state rm module.storage.aws_cloudfront_distribution.frontend

# Apply to recreate CloudFront
terraform apply

# Verify CloudFront in console
```

3. **Check S3 bucket doesn't have conflicting attributes:**
```bash
# List S3 bucket details
aws s3api head-bucket --bucket prod-frontend --region us-east-1

# Check Terraform state
terraform state show module.storage.aws_s3_bucket.frontend
```

**Prevention Going Forward:**
- Always use fixed names for critical resources (S3, CloudFront)
- Avoid depending on `data` sources for resource IDs when possible
- Keep origins ordered consistently (stable origins first)
- Use explicit `depends_on` for cross-module resource dependencies
- Test `terraform plan` before `terraform apply`
# StartTech Operations Runbook

Complete operational guide for running, monitoring, troubleshooting, and scaling the StartTech Much-To-Do application.

## Table of Contents
1. [Quick Reference](#quick-reference)
2. [Pre-Deployment Checklist](#pre-deployment-checklist)
3. [Deployment Procedures](#deployment-procedures)
4. [Scaling Operations](#scaling-operations)
5. [Monitoring & Alerting](#monitoring--alerting)
6. [Troubleshooting](#troubleshooting)
7. [Incident Response](#incident-response)
8. [Maintenance](#maintenance)
9. [Rollback Procedures](#rollback-procedures)
10. [Access & Security](#access--security)

---

## Quick Reference

### Critical URLs and Endpoints

```bash
# ALB DNS (replace with actual)
ALB_DNS=much-to-do-alb-1234567890.us-east-1.elb.amazonaws.com

# CloudFront Domain
CLOUDFRONT_DOMAIN=d123abc456.cloudfront.net

# API Base URL
API_URL=http://${ALB_DNS}

# Health Endpoints
curl http://${ALB_DNS}/health
curl http://${ALB_DNS}/api/health
```

### AWS Console Quick Links
- EC2 Dashboard: https://console.aws.amazon.com/ec2/
- CloudWatch: https://console.aws.amazon.com/cloudwatch/
- ALB: https://console.aws.amazon.com/ec2/v2/home#LoadBalancers
- Auto Scaling: https://console.aws.amazon.com/ec2/v2/home#AutoScalingGroups
- CloudFront: https://console.aws.amazon.com/cloudfront/
- S3: https://console.aws.amazon.com/s3/

---

## Pre-Deployment Checklist

### Prerequisites
- [ ] AWS account with appropriate IAM permissions
- [ ] Terraform >= 1.5.0 installed locally
- [ ] AWS CLI >= 2.0 configured with credentials
- [ ] Git repository configured with remotes
- [ ] GitHub Secrets configured in repository
- [ ] Docker images built and pushed to ECR
- [ ] Frontend build artifacts ready in S3

### Configuration Validation

```bash
# Check Terraform configuration
cd terraform/
terraform validate

# Check formatting
terraform fmt -recursive .

# Run linting
tflint

# Test AWS credentials
aws sts get-caller-identity

# Verify required secrets exist
aws secretsmanager list-secrets
```

---

## Deployment Procedures

### Initial Deployment

```bash
# 1. Initialize Terraform
cd starttech-infra/terraform/
terraform init

# 2. Review plan
terraform plan -out=tfplan

# 3. Review outputs
terraform plan -out=tfplan -no-color > deployment-plan.txt
cat deployment-plan.txt

# 4. Apply changes
terraform apply tfplan

# 5. Get outputs
terraform output > ../infrastructure-outputs.json
```

### Accessing Terraform State

```bash
# View current state
terraform state list

# Inspect specific resource
terraform state show 'module.compute.aws_autoscaling_group.backend'

# Get output values
terraform output load_balancer_dns
terraform output cloudfront_domain_name
terraform output s3_bucket_name

# Backup state before changes
terraform state pull > backup-state.json
```

### Deploying Updates via GitHub Actions

```bash
# 1. Push code to main branch
git add .
git commit -m "Update infrastructure"
git push origin main

# 2. Monitor GitHub Actions
# Go to repository → Actions → Infrastructure Deployment

# 3. Verify in AWS
aws ec2 describe-instances --filters "Name=tag:Name,Values=prod-backend" \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name,PrivateIpAddress]'
```

---

## Scaling Operations

### Auto Scaling Group Management

#### View Current Configuration

```bash
# Get ASG details
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "prod-backend-asg" \
  --query 'AutoScalingGroups[0]'

# Check current instances
aws autoscaling describe-auto-scaling-instances \
  --query 'AutoScalingInstances[?AutoScalingGroupName==`prod-backend-asg`]'

# View scaling policies
aws autoscaling describe-policies \
  --auto-scaling-group-name "prod-backend-asg"
```

#### Manual Scaling

```bash
# Scale up to 5 instances
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name prod-backend-asg \
  --desired-capacity 5

# Scale down to 2 instances
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name prod-backend-asg \
  --desired-capacity 2

# Monitor scaling activity
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name prod-backend-asg \
  --max-records 10
```

#### Adjust Scaling Policies

```bash
# Update target CPU utilization
aws autoscaling put-scaling-policy \
  --auto-scaling-group-name prod-backend-asg \
  --policy-name cpu-tracking \
  --policy-type TargetTrackingScaling \
  --target-tracking-configuration '{
    "TargetValue": 65.0,
    "PredefinedMetricSpecification": {
      "PredefinedMetricType": "ASGAverageCPUUtilization"
    },
    "ScaleOutCooldown": 60,
    "ScaleInCooldown": 300
  }'
```

#### Update Launch Template

```bash
# Create new version with updated settings
terraform apply -target='module.compute.aws_launch_template.backend'

# The ASG will use new instances for scaling
# Existing instances will continue running
# Use rolling update to refresh all instances
```

---

## Monitoring & Alerting

### CloudWatch Dashboards

#### Viewing Metrics

```bash
# Get dashboard names
aws cloudwatch list-dashboards

# View specific dashboard
aws cloudwatch get-dashboard --dashboard-name "StartTech-Production"
```

#### Key Metrics to Monitor

1. **ALB Metrics**
   - RequestCount (should be stable)
   - TargetResponseTime (should be < 200ms)
   - HTTPCode_Target_5XX_Count (should be 0)
   - UnHealthyHostCount (should be 0)

2. **EC2 Metrics**
   - CPUUtilization (target 30-70%)
   - NetworkIn/Out
   - DiskReadBytes/WriteBytes

3. **Application Metrics**
   - Request latency
   - Error count
   - Database query time
   - Cache hit ratio

### CloudWatch Logs Insights Queries

#### Application Error Analysis
```sql
fields @timestamp, @message, level, error_type
| filter level = "ERROR"
| stats count() as error_count by error_type
| sort error_count desc
```

#### Performance Analysis
```sql
fields @duration, @status
| filter @duration > 1000
| stats avg(@duration) as avg_ms, max(@duration) as max_ms, pct(@duration, 95) as p95_ms by @status
```

#### Request Volume Analysis
```sql
fields @timestamp, @message
| stats count() as request_count by bin(5m)
```

#### Database Query Analysis
```sql
fields @timestamp, database_query_time, query_type
| filter database_query_time > 100
| stats avg(database_query_time) as avg_ms, count() as slow_queries by query_type
```

#### Error Rate Calculation
```sql
fields @timestamp, @status
| stats count() as total_requests, sum((@status >= 500) * 1) as server_errors by bin(1m)
| fields @timestamp, total_requests, server_errors, (server_errors * 100.0 / total_requests) as error_rate_pct
```

### Setting Up Alarms

```bash
# High CPU utilization alarm
aws cloudwatch put-metric-alarm \
  --alarm-name prod-backend-high-cpu \
  --alarm-description "Alert when CPU > 80%" \
  --metric-name CPUUtilization \
  --namespace AWS/EC2 \
  --statistic Average \
  --period 300 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2

# Unhealthy targets alarm
aws cloudwatch put-metric-alarm \
  --alarm-name prod-alb-unhealthy-targets \
  --alarm-description "Alert when unhealthy targets > 0" \
  --metric-name UnHealthyHostCount \
  --namespace AWS/ApplicationELB \
  --statistic Average \
  --period 60 \
  --threshold 0 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 1

# Error rate alarm
aws cloudwatch put-metric-alarm \
  --alarm-name prod-backend-error-rate \
  --alarm-description "Alert when 5xx error rate > 5%" \
  --metric-name HTTPCode_Target_5XX_Count \
  --namespace AWS/ApplicationELB \
  --statistic Sum \
  --period 300 \
  --threshold 25 \
  --comparison-operator GreaterThanThreshold
```

---

## Troubleshooting

### Common Issues

#### Issue: Unhealthy Targets in ALB

**Symptoms**: Target group showing red/unhealthy

**Diagnosis**:
```bash
# Check target health
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:region:account:targetgroup/tg-name/id

# SSH to instance and check application
aws ssm start-session --target i-xxxxxxxxx

# Inside instance:
docker ps
docker logs container-name
curl http://localhost:8080/health
```

**Resolution**:
1. Check application logs in CloudWatch
2. Verify environment variables are set
3. Restart container: `docker restart container-name`
4. If persistent, terminate instance (ASG will replace it)

#### Issue: ALB DNS Not Resolving

**Symptoms**: Cannot resolve ALB DNS name

**Diagnosis**:
```bash
nslookup much-to-do-alb-1234567890.us-east-1.elb.amazonaws.com
dig much-to-do-alb-1234567890.us-east-1.elb.amazonaws.com
```

**Resolution**:
1. Wait 5-10 minutes for DNS propagation
2. Check if ALB actually exists: `aws elbv2 describe-load-balancers`
3. Verify security group allows inbound 80/443

#### Issue: CloudFront Returns 403 Forbidden

**Symptoms**: Frontend returns 403 when accessing via CloudFront

**Diagnosis**:
```bash
# Check S3 bucket policy
aws s3api get-bucket-policy --bucket starttech-frontend-prod

# Check CloudFront origins
aws cloudfront get-distribution --id E1234ABCD | jq '.Distribution.DistributionConfig.Origins'

# Test direct S3 access
curl https://starttech-frontend-prod.s3.amazonaws.com/index.html
```

**Resolution**:
1. Ensure S3 bucket has public access block disabled
2. Verify CloudFront OAI permissions
3. Check Origin Access Identity settings
4. Invalidate cache: `aws cloudfront create-invalidation --distribution-id E1234ABCD --paths "/*"`

#### Issue: High Memory Usage in EC2

**Symptoms**: Memory approaching 100%, instance may swap

**Diagnosis**:
```bash
# Inside EC2 instance
free -m
ps aux --sort=-%mem | head -20
docker stats
```

**Resolution**:
1. Identify memory leak in application logs
2. Increase instance size: `terraform apply -var='instance_type=t3.small'`
3. Reduce container memory limits if applicable
4. Enable memory-based autoscaling policy

#### Issue: Database Connection Errors

**Symptoms**: Application logs show database connection errors

**Diagnosis**:
```bash
# Check security group allows traffic
aws ec2 describe-security-groups --group-ids sg-xxxxx

# Test database connectivity from EC2
aws ssm start-session --target i-xxxxxxxxx
nc -zv mongodb-host 27017
```

**Resolution**:
1. Verify database security group allows backend EC2 access
2. Check database is running and accessible
3. Verify connection string in environment variables
4. Check database auth credentials

#### Issue: S3 Deployment Failing

**Symptoms**: GitHub Actions fails at S3 sync step

**Diagnosis**:
```bash
# Check GitHub Actions logs for specific error
# Common errors:
# - Access Denied: IAM permissions missing
# - Bucket doesn't exist: S3 bucket name wrong
# - Region mismatch: Bucket in different region
```

**Resolution**:
1. Verify IAM role has S3 permissions
2. Confirm bucket name in GitHub Secrets
3. Check bucket region matches AWS_REGION
4. Ensure bucket exists: `aws s3 ls s3://starttech-frontend-prod`

---

## Incident Response

### High CPU Utilization

**Alert Triggered**: CPU > 80% for 10 minutes

**Immediate Actions**:
```bash
# 1. Check what's consuming CPU
aws ec2 describe-instances --filters "Name=tag:Environment,Values=prod" \
  --query 'Reservations[*].Instances[*].[InstanceId,CpuOptions]'

# 2. Get detailed metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=AutoScalingGroupName,Value=prod-backend-asg \
  --statistics Average \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300

# 3. Check application logs
aws logs tail /aws/ec2/prod/backend --follow
```

**Response**:
1. Immediate: Manual scale up `set-desired-capacity` to 5
2. Short-term: Investigate application code for inefficiencies
3. Long-term: Optimize queries, add caching, increase baseline capacity

### Error Rate Spike

**Alert Triggered**: 5xx errors > 5% for 5 minutes

**Immediate Actions**:
```bash
# 1. Check ALB logs
aws logs tail /aws/alb/prod --follow

# 2. Check application logs for errors
aws logs tail /aws/ec2/prod/backend --follow --filter-pattern "ERROR"

# 3. Check database connectivity
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --statistics Average

# 4. Check recent deployments
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name prod-backend-asg \
  --max-records 5
```

**Response**:
1. Check recent code changes in GitHub
2. Review application error logs for patterns
3. If database issue: restart application
4. If code issue: trigger rollback (see Rollback section)

### Database Connection Pool Exhausted

**Alert Triggered**: Database connection errors in logs

**Immediate Actions**:
```bash
# 1. Check current connections
aws ssm start-session --target i-xxxxxxxxx
psql -h database-host -U username -c "SELECT * FROM pg_stat_activity"

# 2. Check connection pool settings
grep -i pool /path/to/app/config.yml

# 3. Monitor new connections
watch "psql -h database-host -U username -c 'SELECT count(*) FROM pg_stat_activity'"
```

**Response**:
1. Increase connection pool size in application config
2. Identify and terminate idle connections
3. Restart application: `docker restart container-name`
4. Add connection pooling service (PgBouncer) if needed

---

## Maintenance

### Regular Tasks

#### Daily
- [ ] Monitor ALB health (all targets green)
- [ ] Check error rate (< 0.1%)
- [ ] Verify backups completed
- [ ] Review CPU and memory usage

#### Weekly
- [ ] Review CloudWatch logs for patterns
- [ ] Analyze performance trends
- [ ] Check for pending updates/patches
- [ ] Test rollback procedure

#### Monthly
- [ ] Run full disaster recovery test
- [ ] Review security group rules
- [ ] Check IAM permissions for changes
- [ ] Performance optimization review
- [ ] Cost analysis

### Updating Infrastructure

```bash
# 1. Make changes to Terraform
vi terraform/variables.tf  # or update terraform.tfvars

# 2. Plan changes
terraform plan -out=update.tfplan

# 3. Review changes carefully
cat update.tfplan

# 4. Apply to staging first (optional)
# terraform workspace select staging
# terraform apply -var-file=staging.tfvars

# 5. Apply to production
terraform apply update.tfplan

# 6. Verify changes
terraform output
aws ec2 describe-instances --query 'Reservations[*].Instances[*].[InstanceId,InstanceType,State.Name]'
```

### Database Maintenance

```bash
# Backup database
mongodump --uri="mongodb+srv://user:pass@host/database" --out=/backups/db-backup-$(date +%Y%m%d)

# Check database size
db.stats()

# Rebuild indexes
db.collection_name.reIndex()

# Remove old documents
db.collection_name.deleteMany({created_at: {$lt: new Date(Date.now() - 90*24*60*60*1000)}})
```

---

## Rollback Procedures

### Application Rollback (Previous Docker Image)

```bash
# 1. Identify current image
aws ec2 describe-launch-template-versions \
  --launch-template-name prod-backend-lt \
  --query 'LaunchTemplateVersions[0].LaunchTemplateData.ImageId'

# 2. Get previous good image
git log --oneline backend/Dockerfile | head -5

# 3. Tag previous image
docker tag starttech-backend:v1.0.0 starttech-backend:latest
docker push ghcr.io/yourorg/starttech-backend:latest

# 4. Update launch template
terraform apply -target='module.compute.aws_launch_template.backend'

# 5. Terminate instances to force recreation
aws ec2 terminate-instances --instance-ids i-xxxxxxx i-yyyyyyy

# 6. ASG will launch new instances with previous image
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name prod-backend-asg \
  --max-records 5
```

### Infrastructure Rollback (Previous Terraform State)

```bash
# 1. Backup current state
terraform state pull > current-state.json

# 2. Review git history for previous working state
git log --oneline terraform/

# 3. Revert to previous commit
git revert HEAD  # or git reset --hard HEAD~1

# 4. Plan changes
terraform plan -out=rollback.tfplan

# 5. Apply rollback
terraform apply rollback.tfplan

# 6. Verify system
curl http://ALB_DNS/health
```

### Complete Infrastructure Rebuild

```bash
# 1. Destroy existing infrastructure
terraform destroy -auto-approve

# 2. Verify AWS resources deleted
aws ec2 describe-instances --filters "Name=tag:Environment,Values=prod"
aws elbv2 describe-load-balancers --query 'LoadBalancers[?Tags[?Key==`Environment` && Value==`prod`]]'

# 3. Rebuild from scratch
terraform apply -auto-approve

# 4. Verify new deployment
terraform output
aws ec2 describe-instances --query 'Reservations[*].Instances[*].[InstanceId,State.Name,PrivateIpAddress]'
```

---

## Access & Security

### SSH Access to EC2 Instances

```bash
# Using AWS Systems Manager Session Manager (recommended)
aws ssm start-session --target i-xxxxxxxxx

# Or using SSH with key pair
ssh -i ~/keys/prod-backend.pem ec2-user@10.0.x.x

# Within session, check application
docker ps
docker logs -f container-name
tail -f /var/log/messages
```

### Database Access

```bash
# MongoDB via EC2 jump host
aws ssm start-session --target i-xxxxxxxxx

# Inside instance:
mongosh "mongodb+srv://user:pass@host/database"

# Query examples
db.todos.find({userId: "user123"})
db.todos.countDocuments()
```

### Log Access

```bash
# View recent logs
aws logs tail /aws/ec2/prod/backend --follow

# Search logs with pattern
aws logs filter-log-events \
  --log-group-name /aws/ec2/prod/backend \
  --filter-pattern "ERROR"

# Export logs to S3
aws logs create-export-task \
  --log-group-name /aws/ec2/prod/backend \
  --from $(date -d '7 days ago' +%s)000 \
  --to $(date +%s)000 \
  --destination starttech-logs-backup \
  --destination-prefix logs/backend
```

### Security Best Practices

```bash
# Rotate credentials regularly
# Update security groups: remove unused ports
aws ec2 authorize-security-group-ingress --group-id sg-xxxxx --protocol tcp --port 22 --cidr 0.0.0.0/0  # ⚠️ Avoid this

# Better: restrict to specific IPs
aws ec2 authorize-security-group-ingress --group-id sg-xxxxx --protocol tcp --port 22 --cidr 203.0.113.0/24

# Audit IAM permissions
aws iam get-user-policy --user-name deployment-user --policy-name StartTechDeployPolicy

# Enable MFA for root account
# Monitor CloudTrail for unauthorized access
aws cloudtrail lookup-events --max-results 50
```

---

## Contact & Escalation

For issues:
1. Check CloudWatch logs and dashboards
2. Review this runbook troubleshooting section
3. Contact infrastructure team
4. Open AWS Support case if needed

---
