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
aws ecr get-login-password --region ${AWS_REGION:-us-east-1} | docker login --username AWS --password-stdin $(echo ${docker_image} | cut -d'/' -f1)
docker pull ${docker_image}
docker run -d \
  --name backend \
  -p 8080:8080 \
  --restart always \
  -e ENVIRONMENT=${environment} \
  ${docker_image}
