# VPC
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/18"

  tags = {
    Name = "Main VPC"
  }
}

resource "aws_subnet" "public01" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-1a"
  tags = {
    Name = "Public01"
  }
}

resource "aws_subnet" "private01" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "us-east-1a"
  tags = {
    Name = "Private01"
  }
}

resource "aws_subnet" "public02" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.3.0/24"
  availability_zone = "us-east-1b"
  tags = {
    Name = "Public02"
  }
}

resource "aws_internet_gateway" "ig1" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "ig1"
  }
}

resource "aws_route_table" "test-route-table" {
  vpc_id = aws_vpc.main.id

  route {
  cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.ig1.id
  }

  tags = {
    "Name" = "tf-route-table-test"
  }
}

resource "aws_route_table_association" "public01" {
  subnet_id      = aws_subnet.public01.id
  route_table_id = aws_route_table.test-route-table.id
}

resource "aws_route_table_association" "public02" {
  subnet_id      = aws_subnet.public02.id
  route_table_id = aws_route_table.test-route-table.id
}



resource "aws_eip" "tf-eip" {
  vpc      = true
}


resource "aws_nat_gateway" "nat-gw1" {
  allocation_id = aws_eip.tf-eip.id
  subnet_id     = aws_subnet.public01.id

  tags = {
    Name = "tf-nat"
  }
  depends_on = [aws_internet_gateway.ig1]
}


resource "aws_route_table" "tf-private-route-table" {
  vpc_id = aws_vpc.main.id

  route {
  cidr_block = "0.0.0.0/0"
  nat_gateway_id = aws_nat_gateway.nat-gw1.id
  }

  tags = {
    "Name" = "tf-private-route-table"
  }
}

resource "aws_route_table_association" "private01" {
  subnet_id      = aws_subnet.private01.id
  route_table_id = aws_route_table.tf-private-route-table.id
}


#14. Create Security Group to allow port 80, 443
resource "aws_security_group" "deploy9-private-security-group" {
  name = "project1-web-traffic"
  description = "Allow web traffic"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port = 80
    protocol = "tcp"
    security_groups = [aws_security_group.deploy9-alb-security-group.id]
    to_port = 80
  } 
  
  egress {
    from_port = 0
    protocol = "-1"
    ipv6_cidr_blocks = ["::/0"]
    self = false
    to_port = 0
  } 

  tags = {
    "Name" = "deploy9-allow-web-traffic"
  }

}
# CREATE EC2
resource "aws_instance" "EC2" {
  ami           = "ami-083654bd07b5da81d"
  instance_type = "t2.micro"
  subnet_id = aws_subnet.private01.id
  vpc_security_group_ids = [aws_security_group.deploy9-private-security-group.id]

  tags = {
    Name = "App EC2"
  }
}

resource "aws_security_group" "deploy9-alb-security-group" {
  name = "alb-sg"
  description = "Allow web traffic into app ec2"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port = 80
    protocol = "tcp"
    to_port = 80
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  } 
  
  tags = {
    "Name" = "deploy9-alb-sg"
  }
}


resource "aws_security_group_rule" "alb-to-ec2" {
  type              = "egress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  source_security_group_id   = aws_security_group.deploy9-private-security-group.id
  security_group_id = aws_security_group.deploy9-alb-security-group.id
}

#AppLB
resource "aws_lb" "deploy9-alb" {
  name               = "deploy9-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.deploy9-alb-security-group.id]

  subnet_mapping {
    subnet_id            = aws_subnet.public01.id
  }

  subnet_mapping {
    subnet_id            = aws_subnet.public02.id
  }

  tags = {
    Environment = "private-alb"
  }
}

#target groups
resource "aws_lb_target_group" "deploy9-target" {
  name     = "deploy9-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
}

resource "aws_lb_target_group_attachment" "test" {
  target_group_arn = aws_lb_target_group.deploy9-target.arn
  target_id        = aws_instance.EC2.id
  port             = 80
}

resource "aws_lb_listener" "alb-listener" {
  load_balancer_arn = aws_lb.deploy9-alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.deploy9-target.arn
  }
}
########################

#internal 
resource "aws_subnet" "internal01" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.5.0/24"
  availability_zone = "us-east-1a"
  tags = {
    Name = "Internal01"
  }
}

resource "aws_subnet" "internal02" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.6.0/24"
  availability_zone = "us-east-1b"
  tags = {
    Name = "Internal02"
  }
}

resource "aws_db_subnet_group" "subnet-group-rds" {
  name       = "deploy9-subnet-group"
  subnet_ids = [aws_subnet.internal01.id, aws_subnet.internal02.id]

  tags = {
    Name = "Deploy9 DB subnet group"
  }
}

resource "aws_db_instance" "postgres-rds" {
  allocated_storage    = 20
  engine               = "postgres"
  engine_version       = "9.6.20"
  instance_class       = "db.t2.micro"
  name                 = "deploy9db"
  username             = "deploy9"
  password             = "deploy9-postgresql123!"
  multi_az             = true
  vpc_security_group_ids = [aws_security_group.deploy9-db-security-group.id]
  db_subnet_group_name = "deploy9-subnet-group"
  skip_final_snapshot  = true
}

resource "aws_security_group" "deploy9-db-security-group" {
  name = "postgres-sg"
  vpc_id = aws_vpc.main.id
  
  ingress {
    from_port = 5432
    protocol = "tcp"
    security_groups = [aws_security_group.deploy9-alb-security-group.id]
    to_port = 5432
  } 
  
  tags = {
    "Name" = "deploy9-db-sg"
  }
}
