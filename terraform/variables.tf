variable "aws_region" {
  description = "Région AWS où déployer les ressources"
  type        = string
  default     = "eu-west-3"
}

variable "aws_access_key" {
  description = "Clé d'accès AWS"
  type        = string
  sensitive   = true
}

variable "aws_secret_key" {
  description = "Clé secrète AWS"
  type        = string
  sensitive   = true
}

variable "environment" {
  description = "Environnement de déploiement (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Nom du projet, utilisé pour nommer les ressources"
  type        = string
  default     = "flask-cloud-app"
}

variable "instance_type" {
  description = "Type d'instance EC2"
  type        = string
  default     = "t3.micro"
}

variable "key_pair_name" {
  description = "Nom de la paire de clés SSH"
  type        = string
  default     = "flask-app-key"
}

variable "ssh_public_key_path" {
  description = "Chemin vers la clé publique SSH locale"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "s3_bucket_name" {
  description = "Nom du bucket S3 (doit être unique mondialement)"
  type        = string
  default     = "flask-app-static-files-2025"
}

variable "db_enabled" {
  description = "Activer ou non la base de données RDS"
  type        = bool
  default     = true
}

variable "db_engine" {
  description = "Moteur de base de données (postgres ou mysql)"
  type        = string
  default     = "postgres"
}

variable "db_instance_class" {
  description = "Classe d'instance RDS"
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "Nom de la base de données"
  type        = string
  default     = "flaskdb"
}

variable "db_username" {
  description = "Nom d'utilisateur de la base de données"
  type        = string
  default     = "flaskadmin"
}

variable "db_password" {
  description = "Mot de passe de la base de données"
  type        = string
  sensitive   = true
  default     = "ChangeMe123!"
}
