
# Display the Application Load Balancer DNS name
output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.httpd.dns_name
}

# Display the website URL
output "website_url" {
  description = "URL for the Morays website"
  value       = "http://${aws_lb.httpd.dns_name}"
}

# Display the ECS cluster name
output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.website.name
}
