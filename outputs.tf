output "vpc_id" {
  description = "An ID of VPC"
  value       = aws_vpc.VPC1.id
}

output "subnet_pub_ids" {
  description = "An IDs of public subnets"
  value       = [aws_subnet.subnet-pub-1.id, aws_subnet.subnet-pub-2.id]
}
