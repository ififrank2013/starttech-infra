# System Architecture

## Overview

This document describes the complete system architecture for the StartTech Much-To-Do application, including all components, their interactions, and deployment topology.

## Architecture Diagram

```
┌────────────────────────────────────────────────────────────────┐
│                        Internet Users                           │
└────────────────────┬─────────────────────────────────────────┘
                     │
                ┌────▼─────────────┐
                │   Route 53       │ (DNS)
                │   (Optional)     │
                └────┬─────────────┘
                     │
        ┌────────────▼────────────┐
        │  CloudFront CDN          │
        │  - Global distribution   │
        │  - Caching               │
        │  - Security              │
        └────────────┬─────────────┘
                     │
    ┌────────────────┴────────────────────┐
    │                                     │
┌───▼────────────┐        ┌──────────────▼──┐
│  S3 Bucket     │        │   ALB            │
│  - index.html  │        │   - Route /api   │
│  - CSS/JS      │        │   - Health check │
│  - Assets      │        │   - SSL (opt)    │
└────────────────┘        └──────┬───────────┘
                                 │
                    ┌────────────┼────────────┐
                    │            │            │
                 ┌──▼──┐    ┌──▼──┐    ┌──▼──┐
                 │ EC2 │    │ EC2 │    │ EC2 │
                 │ i-1 │    │ i-2 │    │ i-3 │
                 └──┬──┘    └──┬──┘    └──┬──┘
                    │         │         │
                    └─────────┬─────────┘
                         ┌────▼─────────┐
                         │   Subnet     │
                         │   10.0.10/24 │
                         └──────────────┘
                              │
         ┌────────────────────┼────────────────────┐
         │                    │                    │
    ┌────▼──────┐   ┌─────────▼────┐   ┌──────────▼──┐
    │   Redis   │   │   MongoDB    │   │ CloudWatch  │
    │ ElastiCache│   │   Atlas      │   │ Logs/Metrics│
    │ :6379     │   │   :27017     │   │             │
    └───────────┘   └──────────────┘   └─────────────┘
```

## Component Details

### Frontend Layer

#### S3 Bucket
- **Purpose**: Static file hosting
- **Config**: 
  - Website configuration enabled
  - Public read access via CloudFront OAI
  - Versioning enabled
  - Server-side encryption enabled

#### CloudFront Distribution
- **Purpose**: Global content delivery and caching
- **Features**:
  - Origins: S3 bucket for static content
  - Origin Access Identity for secure S3 access
  - Cache behaviors for static assets and index.html
  - Security headers
  - HTTP/2 support
  - IPv6 support
- **Performance**:
  - TTL for static assets: 1 year (31536000s)
  - TTL for index.html: no cache (must-revalidate)
  - Compression enabled

### Networking Layer

#### VPC
- **CIDR**: 10.0.0.0/16
- **Subnets**:
  - Public: 10.0.1.0/24, 10.0.2.0/24 (ALB)
  - Private: 10.0.11.0/24, 10.0.12.0/24 (EC2, ElastiCache)
- **NAT Gateways**: One per AZ in public subnets
- **Route Tables**: Separate for public and private subnets

#### Security Groups

**ALB Security Group**
- Inbound: 80 (HTTP), 443 (HTTPS)
- Outbound: All

**Backend Security Group**
- Inbound: 8080 from ALB, 22 from anywhere
- Outbound: All

**Redis Security Group**
- Inbound: 6379 from Backend only
- Outbound: All

**MongoDB Security Group**
- Inbound: 27017 from Backend only
- Outbound: All

### Application Load Balancer (ALB)

- **Type**: Application Load Balancer
- **Listeners**:
  - Port 80 → Backend target group
  - Port 443 → Backend target group (optional)
- **Target Group**:
  - Protocol: HTTP on port 8080
  - Health check: `/health` endpoint
  - Healthy threshold: 2
  - Unhealthy threshold: 2
  - Timeout: 3 seconds
  - Interval: 30 seconds
  - Success codes: 200

### Compute Layer

#### EC2 Launch Template
- **AMI**: Amazon Linux 2
- **Instance Type**: t3.micro (configurable)
- **Network**: Private subnets
- **IAM Role**:
  - CloudWatch Logs write access
  - ECR image pull access
  - EC2 tagging access
- **User Data**:
  - Docker installation
  - CloudWatch Logs agent setup
  - Application container startup

#### Auto Scaling Group (ASG)
- **Launch Template**: Latest version
- **Subnets**: All private subnets
- **Scaling**:
  - Min: 1 instance
  - Max: 4 instances
  - Desired: 2 instances
  - Health check: ELB (300s grace period)
- **Policies**:
  - Scale up when CPU > 70% for 2 minutes
  - Scale down when CPU < 30% for 2 minutes

### Data Layer

#### Redis (ElastiCache)
- **Engine**: Redis 7.0
- **Node Type**: cache.t3.micro (configurable)
- **Mode**: Standalone (configurable to cluster)
- **Subnet**: Private subnets only
- **Security**: 
  - In-transit encryption enabled
  - At-rest encryption enabled
  - Auth token required
- **Use Cases**:
  - Session storage
  - Cache layer
  - Real-time data

#### MongoDB
- **Deployment**: MongoDB Atlas or EC2
- **Connection**: Private network only
- **Authentication**: Required
- **Collections**:
  - todos
  - users
  - sessions
- **Indexes**: 
  - userId on todos
  - email on users (unique)

### Monitoring & Logging

#### CloudWatch Logs
- **Log Groups**:
  - `/aws/ec2/prod/backend` - Application logs
  - `/aws/alb/prod` - ALB access logs
  - `/aws/elasticache/prod` - Redis metrics
- **Retention**: 7 days (configurable)
- **Insights Queries**:
  - Error count by service
  - Request latency percentiles
  - Failed health checks
  - Database errors
  - Cache hit rates

#### CloudWatch Metrics
- **EC2**: CPU, network, disk I/O
- **ALB**: Request count, latency, target health
- **ElastiCache**: CPU, memory, evictions
- **Custom**: Application-specific metrics

#### CloudWatch Alarms
- **UnhealthyHostCount**: Alert when targets unhealthy
- **RedisEvictions**: Alert on memory pressure
- **ALBTargetResponseTime**: Alert on slow responses
- **ASGGroupTerminatingInstances**: Alert on instance issues

### CI/CD Infrastructure

#### GitHub Actions
- **Frontend Pipeline**: Build, test, deploy to S3
- **Backend Pipeline**: Test, build Docker, deploy to EC2
- **Infrastructure Pipeline**: Terraform plan/apply

#### ECR (Elastic Container Registry)
- **Repository**: `prod-backend`
- **Image scanning**: Enabled (Trivy)
- **Lifecycle**: Keep last 10 tagged images

## Data Flow

### Frontend Request
```
User → CloudFront → S3 → User Browser
                ↓
           Caches responses
           (index.html: no cache, assets: 1 year)
```

### API Request
```
Browser → CloudFront (cache miss) → ALB → EC2 Instance
                                      ↓
                                 Go Application
                                      ↓
                            Redis (cache) + MongoDB
```

### Authentication Flow
```
User Login → EC2 API → MongoDB (verify) → Redis (session)
                                            ↓
                                       Return token
```

## Scalability

### Horizontal Scaling
- **EC2**: Auto Scaling Group (1-4 instances)
- **Redis**: Cluster mode (optional)
- **MongoDB**: Replica sets (Atlas handles this)

### Vertical Scaling
- **EC2**: Change instance type in launch template
- **Redis**: Upgrade node type
- **MongoDB**: Upgrade cluster tier

## Disaster Recovery

### Backup Strategy
- **Frontend**: S3 versioning enabled
- **Backend Code**: GitHub repository
- **Database**: MongoDB Atlas automatic backups
- **Configuration**: Terraform state in S3

### Recovery Procedures
- **Frontend**: Restore from S3 version or redeploy via CI/CD
- **Backend**: Redeploy from GitHub Actions
- **Database**: MongoDB Atlas point-in-time restore
- **Infrastructure**: Terraform re-apply from state

## Security Considerations

### Network Security
- Private subnets for application/data
- Security groups for each tier
- NAT gateways for outbound traffic
- VPC endpoints for AWS services (optional)

### Data Security
- Database passwords via Secrets Manager
- Redis auth token required
- S3 encryption enabled
- CloudFront HTTPS (optional)

### Access Control
- IAM roles for EC2
- Least-privilege policies
- GitHub Actions OIDC authentication
- CloudTrail logging (recommended)

## Performance Optimization

### Caching
- CloudFront: 1-year TTL for assets
- ElastiCache: Session and data caching
- S3: No cache for index.html (SPA routing)

### Compression
- CloudFront: Gzip compression enabled
- ALB: HTTP/2 support
- Application: Middleware compression

### DNS
- Route 53 (optional) for DNS failover
- CloudFront alias records
- Health check-based routing

## Cost Optimization

### Compute
- t3.micro instances (burstable, cost-effective)
- Auto Scaling to match demand
- Reserved Instances (future option)

### Storage
- S3 intelligent tiering (future)
- S3 lifecycle policies (future)
- CloudFront edge caching

### Database
- MongoDB Atlas shared tier (cost-effective)
- ElastiCache micro instance
- Data lifecycle management

## Monitoring Strategy

### Metrics Collected
1. **Availability**: Instance health, ALB target health
2. **Performance**: Response time, CPU, memory, network
3. **Reliability**: Error rates, failed health checks
4. **Security**: Unauthorized requests, auth failures

### Alert Thresholds
- CPU > 70%: Scale up
- CPU < 30%: Scale down
- Unhealthy targets: Alert immediately
- Redis evictions > 0: Alert
- Response time > 1000ms: Alert

## Future Enhancements

1. **Multi-region**: Global active-active deployment
2. **Kubernetes**: EKS migration for container orchestration
3. **Infrastructure**: Modular Terraform modules
4. **Monitoring**: Custom dashboards and alerts
5. **Security**: WAF on CloudFront, Shield for DDoS
6. **DevOps**: Infrastructure as Code improvements
