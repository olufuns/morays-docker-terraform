# The ALB is the only public entry point.
resource "aws_security_group" "alb" {
  name_prefix = "${var.project_name}-alb-"
  description = "Allow incoming HTTP to the public ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from the internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    description = "Outbound responses to ECS"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.project_name}-alb-sg" }
}

# Tasks have public IPs for image pulls, but port 80 is NOT open directly to the internet.
resource "aws_security_group" "ecs" {
  name_prefix = "${var.project_name}-task-"
  description = "Permit only the ALB to reach Apache"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP only from load balancer"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  egress {
    description = "Allow ECR pulls, CloudWatch, DNS and other outbound HTTPS"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.project_name}-task-sg" }
}