output "vpc_id" {
  description = "An ID of VPC"
  value       = aws_vpc.VPC1.id
}

output "subnet_pub_1_id" {
  description = "An ID of public subnet 1"
  value       = [aws_subnet.subnet-pub-1.id, aws_subnet.subnet-pub-2.id]
}
