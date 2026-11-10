output "website_url" {
  description = "Public HTTP address of the website (no custom domain)."
  value       = "http://${aws_lb.website.dns_name}"
}

output "alb_dns_name" {
  value = aws_lb.website.dns_name
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.website.name
}

output "ecs_service_name" {
  value = aws_ecs_service.website.name
}

output "cloudwatch_log_group" {
  value = aws_cloudwatch_log_group.ecs.name
}

output "image_uri" {
  value = var.image_uri
}

output "vpc_id" {
  value = aws_vpc.main.id
}