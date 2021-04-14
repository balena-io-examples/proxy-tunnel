output "instance_public_ip" {
  description = "Public DNS name assigned to the EC2 instance"
  value       = module.ec2_instance.public_ip[0]
}