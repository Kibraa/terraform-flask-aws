# ============================================================================
# main.tf — Fichier principal : toutes les ressources à créer
# ============================================================================
# Ce fichier contient :
#   1. Le réseau (VPC, Subnet, Internet Gateway, Security Groups)
#   2. La machine virtuelle EC2
#   3. Le bucket S3 (stockage cloud)
#   4. La base de données RDS (optionnelle)
#   5. Le rôle IAM pour que l'EC2 accède au S3
# ============================================================================


# ╔═══════════════════════════════════════════════════════════════════╗
# ║  1. RÉSEAU — VPC, Subnet, Internet Gateway, Route Table         ║
# ╚═══════════════════════════════════════════════════════════════════╝

# --- VPC : le réseau virtuel privé qui isole nos ressources ---
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# --- Subnet public : le sous-réseau où sera la VM ---
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-subnet"
  }
}

# --- Subnet privé #1 pour RDS (nécessite 2 AZ différentes) ---
resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${var.aws_region}a"

  tags = {
    Name = "${var.project_name}-private-subnet-a"
  }
}

# --- Subnet privé #2 pour RDS ---
resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "${var.aws_region}b"

  tags = {
    Name = "${var.project_name}-private-subnet-b"
  }
}

# --- Internet Gateway : pour que la VM accède à Internet ---
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# --- Route Table : diriger le trafic vers Internet ---
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

# --- Associer la route table au subnet public ---
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}


# ╔═══════════════════════════════════════════════════════════════════╗
# ║  2. SECURITY GROUPS — Pare-feu pour la VM et la BDD             ║
# ╚═══════════════════════════════════════════════════════════════════╝

# --- Security Group pour l'EC2 ---
resource "aws_security_group" "ec2_sg" {
  name        = "${var.project_name}-ec2-sg"
  description = "Autoriser SSH (22), HTTP (80) et Flask (5000)"
  vpc_id      = aws_vpc.main.id

  # SSH — pour se connecter à la VM
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # En prod : restreindre à votre IP !
  }

  # HTTP — pour accéder au site web
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Flask — port par défaut de l'application
  ingress {
    description = "Flask App"
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Sortie — autoriser tout le trafic sortant
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

# --- Security Group pour RDS ---
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


# ╔═══════════════════════════════════════════════════════════════════╗
# ║  3. IAM — Rôle pour que l'EC2 accède au S3                      ║
# ╚═══════════════════════════════════════════════════════════════════╝

# --- Rôle IAM : identité que l'EC2 va "assumer" ---
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

# --- Politique IAM : quels droits sur S3 ---
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

# --- Instance Profile : attacher le rôle à l'EC2 ---
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2_s3_role.name
}


# ╔═══════════════════════════════════════════════════════════════════╗
# ║  4. EC2 — La Machine Virtuelle                                  ║
# ╚═══════════════════════════════════════════════════════════════════╝

# --- Récupérer la dernière AMI Ubuntu 22.04 ---
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical (éditeur d'Ubuntu)

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# --- Clé SSH ---
resource "aws_key_pair" "deployer" {
  key_name   = var.key_pair_name
  public_key = file(var.ssh_public_key_path)
}

# --- L'instance EC2 elle-même ---
resource "aws_instance" "flask_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.deployer.key_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  root_block_device {
    volume_size = 20    # 20 Go de disque
    volume_type = "gp3" # SSD rapide
  }

  # --- User Data : script exécuté au premier démarrage de la VM ---
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

  # Attendre que la VM soit bien créée avant de continuer
  depends_on = [
    aws_internet_gateway.main,
    aws_s3_bucket.static_files
  ]
}


# ╔═══════════════════════════════════════════════════════════════════╗
# ║  5. S3 — Stockage Cloud pour fichiers statiques                 ║
# ╚═══════════════════════════════════════════════════════════════════╝

# --- Le Bucket S3 ---
resource "aws_s3_bucket" "static_files" {
  bucket        = var.s3_bucket_name
  force_destroy = true # Permet de détruire le bucket même s'il contient des fichiers

  tags = {
    Name = "${var.project_name}-static-files"
  }
}

# --- Versionning : garder un historique des fichiers ---
resource "aws_s3_bucket_versioning" "static_files" {
  bucket = aws_s3_bucket.static_files.id

  versioning_configuration {
    status = "Enabled"
  }
}

# --- Chiffrement : protéger les données au repos ---
resource "aws_s3_bucket_server_side_encryption_configuration" "static_files" {
  bucket = aws_s3_bucket.static_files.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# --- Bloquer l'accès public (sécurité) ---
resource "aws_s3_bucket_public_access_block" "static_files" {
  bucket = aws_s3_bucket.static_files.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- Créer les "dossiers" dans S3 ---
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


# ╔═══════════════════════════════════════════════════════════════════╗
# ║  6. RDS — Base de Données PostgreSQL (optionnel)                 ║
# ╚═══════════════════════════════════════════════════════════════════╝

# --- Groupe de subnets pour RDS ---
resource "aws_db_subnet_group" "flask_db" {
  count = var.db_enabled ? 1 : 0

  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]

  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}

# --- L'instance RDS ---
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

  skip_final_snapshot = true # Pour le dev — en prod, mettre false !
  multi_az            = false

  tags = {
    Name = "${var.project_name}-database"
  }
}
