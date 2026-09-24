provider "aws" {
  region = var.region
}

data "aws_ami" "amazon_linux" {
  most_recent = true

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  owners = ["amazon"]
}

resource "aws_instance" "bastion_instance" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.bastion_key.id
  vpc_security_group_ids      = [aws_security_group.bastion_sg.id]
  subnet_id                   = aws_subnet.subnet-pub-1.id
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.test_profile.name

  tags = {
    Name    = var.instance_name
    Project = "terraform-3tier"
  }
}

resource "aws_vpc" "VPC1" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name    = "VPC1"
    Project = "terraform-3tier"
  }
}

resource "aws_subnet" "subnet-pub-1" {
  vpc_id                  = aws_vpc.VPC1.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "eu-central-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "public_subnet_1"
  }
}

resource "aws_subnet" "subnet-pub-2" {
  vpc_id                  = aws_vpc.VPC1.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "eu-central-1b"
  map_public_ip_on_launch = true
  tags = {
    Name = "public_subnet_2"
  }
}

resource "aws_subnet" "subnet-priv-1" {
  vpc_id            = aws_vpc.VPC1.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = "eu-central-1a"
  tags = {
    Name = "private_subnet_1"
  }
}

resource "aws_subnet" "subnet-priv-2" {
  vpc_id            = aws_vpc.VPC1.id
  cidr_block        = "10.0.12.0/24"
  availability_zone = "eu-central-1b"
  tags = {
    Name = "private_subnet_2"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.VPC1.id
  tags = {
    Name = "igw"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.VPC1.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "public_route_table"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.VPC1.id
  tags = {
    Name = "private_route_table"
  }
}

resource "aws_route_table_association" "public_subnet_association_1" {
  subnet_id      = aws_subnet.subnet-pub-1.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "public_subnet_association_2" {
  subnet_id      = aws_subnet.subnet-pub-2.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_subnet_association_1" {
  subnet_id      = aws_subnet.subnet-priv-1.id
  route_table_id = aws_route_table.private_route_table.id
}

resource "aws_route_table_association" "private_subnet_association_2" {
  subnet_id      = aws_subnet.subnet-priv-2.id
  route_table_id = aws_route_table.private_route_table.id
}

resource "aws_key_pair" "bastion_key" {
  key_name   = "bastion_key"
  public_key = file(pathexpand("~/.ssh/terraform-3tier.pub"))
}

resource "aws_security_group" "bastion_sg" {
  vpc_id = aws_vpc.VPC1.id
  tags = {
    Name = "bastion_sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_ssh" {
  security_group_id = aws_security_group.bastion_sg.id
  cidr_ipv4         = var.my_ip
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic" {
  security_group_id = aws_security_group.bastion_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "rds_subnet_group"
  subnet_ids = [aws_subnet.subnet-priv-1.id, aws_subnet.subnet-priv-2.id]

  tags = {
    Name = "rds_subnet_group"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "rds_security_group"
  description = "Allow bastion sg inbound traffic"

  vpc_id = aws_vpc.VPC1.id
}

resource "aws_vpc_security_group_ingress_rule" "rds_sg_ingress" {
  security_group_id            = aws_security_group.rds_sg.id
  referenced_security_group_id = aws_security_group.bastion_sg.id
  from_port                    = 3306
  ip_protocol                  = "tcp"
  to_port                      = 3306
}

resource "aws_db_instance" "mysql_db" {
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.id
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  engine                 = "mysql"
  engine_version         = "8.0.46"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  db_name                = var.db_name
  username               = var.db_username
  password               = var.db_password
  publicly_accessible    = false
  multi_az               = false
  skip_final_snapshot    = true
}

resource "aws_s3_bucket" "test_bucket" {
  bucket        = "terraform-3tier-domiendev"
  force_destroy = true

  tags = {
    Name        = "My bucket"
    Environment = "Dev"
  }
}

resource "aws_s3_bucket_public_access_block" "public_access_block_3tier_bucket" {
  bucket = aws_s3_bucket.test_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "test_bucket_versioning" {
  bucket = aws_s3_bucket.test_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

data "aws_iam_policy_document" "trust_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "permissions_policy" {
  statement {
    actions = [
      "s3:ListBucket",
    ]

    resources = [
      aws_s3_bucket.test_bucket.arn
    ]
  }

  statement {
    actions = [
      "s3:GetObject", "s3:PutObject"
    ]

    resources = [
      "${aws_s3_bucket.test_bucket.arn}/*"
    ]
  }
}


resource "aws_iam_role" "instance" {
  name               = "instance_role"
  path               = "/system/"
  assume_role_policy = data.aws_iam_policy_document.trust_policy.json
}

resource "aws_iam_policy" "policy" {
  name        = "test_policy"
  path        = "/"
  description = "My test policy"

  policy = data.aws_iam_policy_document.permissions_policy.json
}

resource "aws_iam_role_policy_attachment" "bastion_s3" {
  role       = aws_iam_role.instance.name
  policy_arn = aws_iam_policy.policy.arn
}

resource "aws_iam_instance_profile" "test_profile" {
  name = "test_profile"
  role = aws_iam_role.instance.name
}

resource "aws_cloudwatch_metric_alarm" "test_alarm" {
  alarm_name                = "terraform-test-alarm"
  comparison_operator       = "GreaterThanOrEqualToThreshold"
  evaluation_periods        = 2
  metric_name               = "CPUUtilization"
  namespace                 = "AWS/EC2"
  period                    = 300
  statistic                 = "Average"
  threshold                 = 80
  alarm_description         = "This metric monitors ec2 cpu utilization"
  insufficient_data_actions = []
  dimensions = {
    InstanceId = aws_instance.bastion_instance.id
  }
}

resource "aws_launch_template" "instance_template" {

  image_id      = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"
  iam_instance_profile {
    arn = aws_iam_instance_profile.test_profile.arn
  }
  key_name  = aws_key_pair.bastion_key.key_name
  user_data = file("${path.module}/userdata.sh")
  vpc_security_group_ids      = [aws_security_group.app_sg.id]
}

resource "aws_security_group" "alb_sg" {
  name   = "alb_sg"
  vpc_id = aws_vpc.VPC1.id

  tags = {
    Name = "terraform-3tier"
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_traffic_ingress" {
  security_group_id = aws_security_group.alb_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "alb_traffic_egress" {
  security_group_id = aws_security_group.alb_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol = "-1"
}

resource "aws_security_group" "app_sg" {
  name   = "app_sg"
  vpc_id = aws_vpc.VPC1.id

  tags = {
    Name = "terraform-3tier"
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_to_app_traffic" {
  security_group_id            = aws_security_group.app_sg.id
  referenced_security_group_id = aws_security_group.alb_sg.id
  from_port                    = 80
  ip_protocol                  = "tcp"
  to_port                      = 80
}

resource "aws_vpc_security_group_ingress_rule" "bastion_to_app_traffic" {
  security_group_id            = aws_security_group.app_sg.id
  referenced_security_group_id = aws_security_group.bastion_sg.id
  from_port                    = 22
  ip_protocol                  = "tcp"
  to_port                      = 22
}

resource "aws_vpc_security_group_egress_rule" "app_traffic_egress" {
  security_group_id = aws_security_group.app_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol = "-1"
}

resource "aws_lb" "test_lb" {
  name               = "test-lb-tf"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.subnet-pub-1.id, aws_subnet.subnet-pub-2.id]
}

resource "aws_lb_target_group" "test_lb_tg" {
  name     = "tf-example-lb-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.VPC1.id
  health_check {
    path = "/"
  }
}

resource "aws_lb_listener" "test_lb_listener" {
  load_balancer_arn = aws_lb.test_lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.test_lb_tg.arn
  }
}

resource "aws_autoscaling_group" "test_ag" {
  name                      = "terraform-3tier-ag"
  max_size                  = 3
  min_size                  = 2
  health_check_type         = "ELB"
  desired_capacity          = 2
  vpc_zone_identifier       = [aws_subnet.subnet-pub-1.id, aws_subnet.subnet-pub-2.id]
  target_group_arns = [aws_lb_target_group.test_lb_tg.arn]

  launch_template {
    id      = aws_launch_template.instance_template.id
    version = "$Latest"
  }

  tag {
    key                 = "Project"
    value               = "terraform-3tier"
    propagate_at_launch = true
  }

  tag {
    key                 = "Name"
    value               = "app-instance"
    propagate_at_launch = true
  }
}
