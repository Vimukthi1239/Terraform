provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "main_vpc" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1a"
}

resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main_vpc.id
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public_association" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_security_group" "elb_sg" {
  vpc_id = aws_vpc.main_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
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

resource "aws_lb" "app_load_balancer" {
  name               = "app-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.elb_sg.id]
  subnets            = [aws_subnet.public_subnet.id, aws_subnet.private_subnet.id]
}

resource "aws_instance" "web_server" {
  ami           = "ami-0c02fb55956c7d316" # Update with a valid AMI ID
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.private_subnet.id
  security_groups = [aws_security_group.elb_sg.id]
}

resource "aws_db_instance" "database" {
  allocated_storage      = 20
  engine                 = "mysql"
  instance_class         = "db.t3.micro"
  identifier             = "appdb-instance"
  username               = "admin"
  password               = "password1234"
  publicly_accessible    = false
  vpc_security_group_ids = [aws_security_group.elb_sg.id]
  skip_final_snapshot    = true
  db_subnet_group_name   = aws_db_subnet_group.db_subnet_group.name
}

resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "db-subnet-group"
  subnet_ids = [aws_subnet.public_subnet.id, aws_subnet.private_subnet.id]
}

resource "aws_dynamodb_table" "app_table" {
  name         = "AppDataTable"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "ID"

  attribute {
    name = "ID"
    type = "S"
  }
}

resource "aws_s3_bucket" "data_bucket" {
  bucket = "appdatabucketexample"
  acl    = "private"
}

resource "aws_lambda_function" "data_processor" {
  function_name = "data-processor"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "index.handler"
  runtime       = "nodejs22.x"
  filename      = "C:/Users/User/OneDrive/Desktop/New folder/lambda-functions/data-processor.zip" # Ensure this path is correct or upload the zip file
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda_exec_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/data-processor"
  retention_in_days = 7
}

resource "aws_kinesis_stream" "data_stream" {
  name        = "app-data-stream"
  shard_count = 1
}

resource "aws_wafv2_web_acl" "web_acl" {
  name        = "webacl"
  scope       = "REGIONAL"
  description = "Web ACL for application security"
  default_action {
    allow {}
  }
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "WebACLMetric"
    sampled_requests_enabled   = true
  }

  rule {
    name     = "IPBlockRule"
    priority = 1
    action {
      block {}
    }
    statement {
      ip_set_reference_statement {
        arn = "arn:aws:wafv2:us-east-1:123456789012:regional/ipset/example-ip-set-id"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "IPBlockRule"
      sampled_requests_enabled   = true
    }
  }
}
