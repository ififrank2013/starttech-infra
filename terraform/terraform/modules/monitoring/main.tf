# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "backend" {
  name              = "/aws/ec2/${var.environment}/backend"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.environment}-backend-logs"
  }
}

resource "aws_cloudwatch_log_group" "alb" {
  name              = "/aws/alb/${var.environment}"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.environment}-alb-logs"
  }
}

# Enable ALB logging to S3
resource "aws_s3_bucket" "alb_logs" {
  bucket        = "${var.environment}-alb-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = {
    Name = "${var.environment}-alb-logs"
  }
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ElastiCache Redis Cluster
resource "aws_elasticache_subnet_group" "redis" {
  name       = "${var.environment}-redis-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "${var.environment}-redis-subnet-group"
  }
}

resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "${var.environment}-redis"
  engine               = "redis"
  node_type            = var.redis_node_type
  num_cache_nodes      = var.redis_num_nodes
  parameter_group_name = "default.redis7"
  engine_version       = "7.0"
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.redis.name
  security_group_ids   = [var.redis_security_group_id]

  automatic_failover_enabled = false
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                 = var.redis_auth_token

  tags = {
    Name = "${var.environment}-redis"
  }
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.environment}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/EC2", "CPUUtilization", { stat = "Average" }],
            ["AWS/ApplicationELB", "TargetResponseTime"],
            ["AWS/ElastiCache", "CPUUtilization", { stat = "Average" }]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Application Performance"
        }
      },
      {
        type = "log"
        properties = {
          query  = "fields @timestamp, @message | stats count() by @logStream"
          region = var.aws_region
          title  = "Backend Logs"
        }
      }
    ]
  })
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_hosts" {
  alarm_name          = "${var.environment}-alb-unhealthy-hosts"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Average"
  threshold           = 1
  alarm_description   = "Alert when ALB has unhealthy hosts"

  dimensions = {
    TargetGroup = var.target_group_name
  }
}

resource "aws_cloudwatch_metric_alarm" "redis_evictions" {
  alarm_name          = "${var.environment}-redis-evictions"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Evictions"
  namespace           = "AWS/ElastiCache"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Alert when Redis keys are being evicted"

  dimensions = {
    CacheClusterId = aws_elasticache_cluster.redis.cluster_id
  }
}

# Log Insights Queries (stored as file)
resource "local_file" "log_insights_queries" {
  filename = "${path.module}/log-insights-queries.txt"

  content = <<-EOT
# Backend Application Errors
fields @timestamp, @message, @logStream
| filter @message like /ERROR/
| stats count() by @logStream

# Request latency
fields @timestamp, @duration
| filter ispresent(@duration)
| stats avg(@duration), max(@duration), pct(@duration, 95)

# Failed health checks
fields @timestamp, @message
| filter @message like /health/ and @message like /failed/
| stats count() by @logStream

# Database connection issues
fields @timestamp, @message
| filter @message like /mongo/ or @message like /database/
| stats count() by @message

# Redis cache hits/misses
fields @timestamp, cacheHit
| stats sum(cacheHit) as hits, sum(!cacheHit) as misses
  EOT
}

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
