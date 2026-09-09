output "vpc_id" {
  description = "An ID of VPC"
  value       = aws_vpc.VPC1.id
}

output "subnet_pub_ids" {
  description = "An IDs of public subnets"
  value       = [aws_subnet.subnet-pub-1.id, aws_subnet.subnet-pub-2.id]
}

output "public_ip_bastion_instance" {
  description = "Public ip of the bastion instance"
  value       = aws_instance.bastion_instance.public_ip
}

output "rds_endpoint" {
  description = "Connection endpoint of the RDS instance"
  value       = aws_db_instance.mysql_db.endpoint
}