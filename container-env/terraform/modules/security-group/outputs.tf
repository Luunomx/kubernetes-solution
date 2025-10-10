output "alb_sg_id" {
  value = aws_security_group.alb_sg.id
}

output "swarm_sg_id" {
  value = aws_security_group.swarm_sg.id
}

output "bastion_sg_id" {
  value = aws_security_group.bastion_sg.id
}
