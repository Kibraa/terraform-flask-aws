resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-subnet"
  }
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${var.aws_region}a"

  tags = {
    Name = "${var.project_name}-private-subnet-a"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "${var.aws_region}b"

  tags = {
    Name = "${var.project_name}-private-subnet-b"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "ec2_sg" {
  name        = "${var.project_name}-ec2-sg"
  description = "Allow SSH (22), HTTP (80) and Flask (5000)"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Flask App"
    from_port   = 5000
    to_port     = 5000
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
    Name = "${var.project_name}-ec2-sg"
  }
}

resource "aws_security_group" "rds_sg" {
  count = var.db_enabled ? 1 : 0

  name        = "${var.project_name}-rds-sg"
  description = "Allow PostgreSQL traffic from EC2 only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from EC2"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-rds-sg"
  }
}

resource "aws_iam_role" "ec2_s3_role" {
  name = "${var.project_name}-ec2-s3-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "s3_access" {
  name = "${var.project_name}-s3-access-policy"
  role = aws_iam_role.ec2_s3_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.static_files.arn,
          "${aws_s3_bucket.static_files.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2_s3_role.name
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_key_pair" "deployer" {
  key_name   = var.key_pair_name
  public_key = file(var.ssh_public_key_path)
}

resource "aws_instance" "flask_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.deployer.key_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/userdata.sh.tpl", {
    s3_bucket_name = var.s3_bucket_name
    db_enabled     = var.db_enabled
    db_host        = var.db_enabled ? aws_db_instance.flask_db[0].address : ""
    db_name        = var.db_name
    db_username    = var.db_username
    db_password    = var.db_password
    aws_region     = var.aws_region
  })

  tags = {
    Name = "${var.project_name}-server"
  }

  depends_on = [
    aws_internet_gateway.main,
    aws_s3_bucket.static_files
  ]
}

resource "aws_s3_bucket" "static_files" {
  bucket        = var.s3_bucket_name
  force_destroy = true

  tags = {
    Name = "${var.project_name}-static-files"
  }
}

resource "aws_s3_bucket_versioning" "static_files" {
  bucket = aws_s3_bucket.static_files.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "static_files" {
  bucket = aws_s3_bucket.static_files.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "static_files" {
  bucket = aws_s3_bucket.static_files.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "images_folder" {
  bucket  = aws_s3_bucket.static_files.id
  key     = "images/"
  content = ""
}

resource "aws_s3_object" "logs_folder" {
  bucket  = aws_s3_bucket.static_files.id
  key     = "logs/"
  content = ""
}

resource "aws_s3_object" "uploads_folder" {
  bucket  = aws_s3_bucket.static_files.id
  key     = "uploads/"
  content = ""
}

resource "aws_db_subnet_group" "flask_db" {
  count = var.db_enabled ? 1 : 0

  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]

  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}

resource "aws_db_instance" "flask_db" {
  count = var.db_enabled ? 1 : 0

  identifier     = "${var.project_name}-db"
  engine         = var.db_engine
  engine_version = var.db_engine == "postgres" ? "16.6" : "8.0.35"
  instance_class = var.db_instance_class

  allocated_storage     = 20
  max_allocated_storage = 50
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.flask_db[0].name
  vpc_security_group_ids = [aws_security_group.rds_sg[0].id]

  skip_final_snapshot = true
  multi_az            = false

  tags = {
    Name = "${var.project_name}-database"
  }
}
