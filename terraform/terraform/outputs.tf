output "load_balancer_dns" {
  description = "DNS name of the load balancer"
  value       = module.compute.load_balancer_dns
}

output "s3_bucket_name" {
  description = "S3 bucket for frontend hosting"
  value       = module.storage.s3_bucket_name
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name"
  value       = module.storage.cloudfront_domain_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = module.storage.cloudfront_distribution_id
}

output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = module.storage.ecr_repository_url
}

output "redis_endpoint" {
  description = "Redis cluster endpoint"
  value       = module.monitoring.redis_endpoint
}

output "backend_log_group" {
  description = "CloudWatch log group for backend"
  value       = module.monitoring.backend_log_group
}

output "dashboard_url" {
  description = "CloudWatch dashboard URL"
  value       = module.monitoring.dashboard_url
}
