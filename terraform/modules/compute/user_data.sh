#!/bin/bash
set -e

# Update system
yum update -y
yum install -y docker awslogs git

# Start Docker
systemctl start docker
systemctl enable docker

# Add ec2-user to docker group
usermod -aG docker ec2-user

# Configure CloudWatch Logs
cat > /etc/awslogs/config/backend.conf <<EOF
[/var/log/docker]
log_group_name = ${log_group}
log_stream_name = backend-$(ec2-metadata --instance-id | cut -d " " -f 2)
datetime_format = %Y-%m-%d %H:%M:%S
file = /var/lib/docker/containers/*/*.log
EOF

# Start awslogs service
systemctl start awslogsd
systemctl enable awslogsd

# Pull and run Docker image
aws ecr get-login-password --region $${AWS_REGION:-us-east-1} | docker login --username AWS --password-stdin $(echo ${docker_image} | cut -d'/' -f1)
docker pull ${docker_image}

# Get ALB DNS name from instance metadata or EC2 tags
ALB_DNS_NAME=$(aws elb describe-load-balancers --region $${AWS_REGION:-us-east-1} --query "LoadBalancerDescriptions[0].DNSName" --output text 2>/dev/null || echo "")

# Get CloudFront URL from EC2 tags or assume standard naming
CLOUDFRONT_URL=$(aws ec2 describe-tags --region $${AWS_REGION:-us-east-1} --filters "Name=key,Values=CloudFrontURL" --query "Tags[0].Value" --output text 2>/dev/null || echo "https://d22r27pmlhadif.cloudfront.net")

docker run -d \
  --name backend \
  -p 8080:8080 \
  --restart always \
  -e ENVIRONMENT=${environment} \
  -e LOG_LEVEL=INFO \
  -e LOG_FORMAT=json \
  -e JWT_SECRET_KEY="your-super-secret-key-that-is-long-and-random-change-this-in-production" \
  -e JWT_EXPIRATION_HOURS=72 \
  -e DB_NAME=muchtoodb \
  -e MONGO_URI="${mongo_uri}" \
  -e REDIS_HOST=prod-redis.tsxflb.ng.0001.use1.cache.amazonaws.com \
  -e REDIS_PORT=6379 \
  -e ENABLE_CACHE=true \
  -e ALLOWED_ORIGINS="https://d22r27pmlhadif.cloudfront.net,https://d22r27pmlhadif.cloudfront.net/" \
  -e COOKIE_DOMAINS="d22r27pmlhadif.cloudfront.net" \
  -e SECURE_COOKIE=true \
  ${docker_image}
