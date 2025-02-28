#CREATING VPC
provider "aws" {
  region = "us-east-1"
}



variable "rds_username" {
  description = "RDS Username"
  type        = string
}

variable "rds_password" {
  description = "RDS Password"
  type        = string
  sensitive   = true
}

variable "rds_dbname" {
  description = "RDS Database Name"
  type        = string
}

variable "rdshost_name" {
  description = "RDS Host Name"
  type        = string
}



# Create the organization
#resource "aws_organizations_organization" "root" {
#  feature_set = "ALL" # Enables all features, including consolidated billing and service control policies
#}

# Create an IAM group
resource "aws_iam_group" "no_cli_access_group" {
  name = "no_cli_access_group"
}

# Attach a policy to deny CLI access
resource "aws_iam_group_policy" "no_cli_access_policy" {
  group = aws_iam_group.no_cli_access_group.name

  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Deny",
        "Action": [
          "iam:CreateAccessKey",
          "iam:UpdateAccessKey",
          "iam:DeleteAccessKey"
        ],
        "Resource": "*"
      }
    ]
  })
}


# Create IAM user: prof
resource "aws_iam_user" "Prof_Sridhar" {
  name = "professor"
}

resource "aws_iam_user_group_membership" "lecturer_group" {
  user = aws_iam_user.Prof_Sridhar.name
  groups = [
    aws_iam_group.no_cli_access_group.name
  ]
}

resource "aws_iam_user_login_profile" "prof_login_profile" {
  user                    = aws_iam_user.Prof_Sridhar.name
  password_length         = 8
  password_reset_required = true
}

resource "aws_iam_user_policy_attachment" "prof_admin_access" {
  user       = aws_iam_user.Prof_Sridhar.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}


# Output the generated password for the 'prof' user
output "prof_password" {
  value       = aws_iam_user_login_profile.prof_login_profile.password
  description = "The generated password for the prof user"
  sensitive   = true
}



resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "MainVPC"
  }
}
# Data Source for Availability Zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Subnets
resource "aws_subnet" "subnets" {
  count = 3  # Create 3 subnets

  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)  # Dynamic CIDR blocks
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  map_public_ip_on_launch = true

  tags = {
    Name = "Subnet-${count.index + 1}"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "MainInternetGateway"
  }
}

# Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"  # Route for all internet traffic
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "PublicRouteTable"
  }
}

# Associate Route Table with Subnets
resource "aws_route_table_association" "subnet1" {
  subnet_id      = aws_subnet.subnets[0].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "subnet2" {
  subnet_id      = aws_subnet.subnets[1].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "subnet3" {
  subnet_id      = aws_subnet.subnets[2].id
  route_table_id = aws_route_table.public.id
}

# Security Group for Web Servers
resource "aws_security_group" "web_sg" {
  vpc_id = aws_vpc.main.id
  name   = "WebSecurityGroup"

  # Ingress Rules (Inbound Traffic)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Allow SSH from anywhere
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Allow HTTP from anywhere
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Allow HTTPS from anywhere
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Allow custom app traffic on port 8080
  }

  # Egress Rules (Outbound Traffic)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]  # Allow all outbound traffic
  }

  tags = {
    Name = "WebSecurityGroup"
  }
}

# Security Group for Database - only allowing traffic from web servers
resource "aws_security_group" "db_sg" {
  vpc_id = aws_vpc.main.id
  name   = "DatabaseSecurityGroup"

  # Ingress rule - allow traffic from web servers only
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]  # Only allow traffic from web security group
  }

  # Egress Rules
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "DatabaseSecurityGroup"
  }
}


# Amazon Linux 2 AMI data source
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# EC2 Instance with Apache
resource "aws_instance" "web_server" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.subnets[0].id

  vpc_security_group_ids = [aws_security_group.web_sg.id]
  
  # User data script to install and start Apache
  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd
              echo "<h1>Hello from Group3 of Final Project</h1>" > /var/www/html/index.html

              echo "RDS_USERNAME=${var.rds_username}" >> /etc/environment
              echo "RDS_PASSWORD=${var.rds_password}" >> /etc/environment
              echo "RDS_DBNAME=${var.rds_dbname}" >> /etc/environment
              echo "RDSHOST_NAME=${var.rdshost_name}" >> /etc/environment

              # Reload environment variables
              source /etc/environment
              EOF

  # You might want to add your key pair name here
  # key_name = "your-key-pair-name"

  tags = {
    Name = "ApacheWebServer"
  }
}

# Output the public IP of the instance
output "web_server_public_ip" {
  value = aws_instance.web_server.public_ip
}

# Output the public DNS of the instance
output "web_server_public_dns" {
  value = aws_instance.web_server.public_dns
}

