terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.10.0"
    }
  }
}

# Configure backend
terraform {
  backend "s3" {
    bucket         = "wordpress-bucket-258773095581"
    key            = "terraform.tfstate"
    region         = "us-east-1"
    # dynamodb_table = "wordpress-table"
  }
}

# Create VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "wordpress_vpc"
  }
}

# Create Public Subnets
resource "aws_subnet" "wordpress_public_subnet1" {
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "eu-west-2a"
  map_public_ip_on_launch = true
  tags = {
    Name = "wordpress_public_subnet1"
  }
}

# Create public subnet 2
resource "aws_subnet" "wordpress_public_subnet2" {
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "eu-west-2b"
  map_public_ip_on_launch = true
  tags = {
    Name = "wordpress_public_subnet2"
  }
}

# Create a VPC Internet Gateway
resource "aws_internet_gateway" "wordpress_internet_gateway" {
  vpc_id = aws_vpc.wordpress_vpc.id

  tags = {
    Name = "main"
  }
}

# Create Public Route Table
resource "aws_route_table" "wordpress_route_table_public" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress_internet_gateway.id
  }
  tags = {
    Name = "wordpress-route-table-public"
  }
}

# Associate public subnet 1 with public route table
resource "aws_route_table_association" "wordpress_public_subnet1_association" {
  subnet_id      = aws_subnet.wordpress_public_subnet1.id
  route_table_id = aws_route_table.wordpress_route_table_public.id
}

# Associate public subnet 2 with public route table
resource "aws_route_table_association" "wordpress_public_subnet2_association" {
  subnet_id      = aws_subnet.wordpress_public_subnet2.id
  route_table_id = aws_route_table.wordpress_route_table_public.id
}

# Create Network ACL
resource "aws_network_acl" "wordpress_network_acl" {
  vpc_id     = aws_vpc.wordpress_vpc.id
  subnet_ids = [aws_subnet.wordpress_public_subnet1.id, aws_subnet.wordpress_public_subnet2.id]
  ingress {
    rule_no    = 100
    protocol   = "-1"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }
  egress {
    rule_no    = 100
    protocol   = "-1"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }
}

# Create Security Group to allow port 22, 80, 443 and 3306
resource "aws_security_group" "wordpress_security_grp_rule" {
  name        = "allow_ssh_http_https"
  description = "Allow SSH, HTTP and HTTPS inbound traffic for private instances"
  vpc_id      = aws_vpc.wordpress_vpc.id
 ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
 ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "wordpress_security_grp_rule"
  }
}

# Create RDS instance
resource "aws_db_instance" "wordpress_rds" {
  allocated_storage    = 10
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t3.micro"
  db_name              = "wordpress_db"
  username             = "admin"
  password             = "test1234"
  parameter_group_name = "default.mysql8.0"
  skip_final_snapshot  = true
  publicly_accessible  = false
  vpc_security_group_ids = [aws_security_group.database_security_grp_rule.id]
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name
  tags = {
    Name = "MYSQL RDS Instance"
  }
}

# Create RDS Subnet Group
resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "wordpress-db-subnet-group"
  subnet_ids = [aws_subnet.wordpress_public_subnet1.id, aws_subnet.wordpress_public_subnet2.id]
  tags = {
    Name = "wordpress-db-subnet-group"
  }
}

# Create Security Group to allow port 3306
resource "aws_security_group" "database_security_grp_rule" {
  name        = "allow_RDS_data"
  description = "Allow inbound RDS data"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# creating instance
resource "aws_instance" "wordpress_server" {
  ami             = "ami-01b8d743224353ffe"
  instance_type   = "t2.micro"
  key_name        = "wordpress_key"
  security_groups = [aws_security_group.wordpress_security_grp_rule.id]
  subnet_id       = aws_subnet.wordpress_public_subnet1.id
  availability_zone = "eu-west-2a"
  associate_public_ip_address = true
  tags = {
    Name   = "wordpress_server"
    source = "terraform"
  }
    user_data = <<-EOF
        #!/bin/bash
        sudo apt-get update
        sudo apt-get install -y docker.io
        sudo systemctl start docker
        sudo apt-get install -y docker.io
        sudo systemctl enable docker
        sudo docker pull wordpress
        sudo docker run -d --name wordpress \
         -e WORDPRESS_DB_HOST=${aws_db_instance.wordpress_rds.endpoint} \
         -e WORDPRESS_DB_USER=admin \
         -e WORDPRESS_DB_PASSWORD=test1234 \
         -e WORDPRESS_DB_NAME=wordpress_db \
         -p 80:80 wordpress
        EOF
}

# Create an Elastic IP
resource "aws_eip" "wordpress_eip" {
}

# Associate the Elastic IP with the instance
resource "aws_eip_association" "wordpress_eip_assoc" {
  instance_id   = aws_instance.wordpress_server.id
  allocation_id = aws_eip.wordpress_eip.id
}

# Create a file to store the IP addresses of the server
resource "local_file" "Ip_address" {
  filename = "host-inventory"
  content  = <<EOT
${aws_instance.wordpress_server.public_ip}
${aws_eip.wordpress_eip.public_ip}
  EOT
}