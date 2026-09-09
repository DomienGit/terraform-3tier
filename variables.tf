variable "instance_name" {
  description = "Value of the EC2 instance's Name tag."
  type        = string
  default     = "bastion_instance"
}

variable "instance_type" {
  description = "The EC2 instance's type."
  type        = string
  default     = "t3.micro"
}

variable "region" {
  description = "The region name"
  type        = string
  default     = "eu-central-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "my_ip" {
  type = string
}

variable "db_name" {
  description = "Name of the database"
  type        = string
  default     = "mysql_db"
}

variable "db_username" {
  description = "Database username"
  type        = string
  default     = "user"
}

variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}

