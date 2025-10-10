output "alb_dns_name" {
  description = "Public DNS of the Application Load Balancer"
  value       = aws_lb.this.dns_name
}
