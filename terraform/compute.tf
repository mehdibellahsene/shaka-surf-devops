# Instances EC2 : load balancer, applications (>=2), base de données, citools.
# AMI Ubuntu 22.04 LTS récupérée dynamiquement.

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Création optionnelle de la paire de clés depuis une clé publique locale.
resource "aws_key_pair" "this" {
  count      = var.ssh_public_key_path == "" ? 0 : 1
  key_name   = var.ssh_key_name
  public_key = file(pathexpand(var.ssh_public_key_path))
}

locals {
  key_name = var.ssh_public_key_path == "" ? var.ssh_key_name : aws_key_pair.this[0].key_name
}

# ---- Load balancer ----
resource "aws_instance" "lb" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type_lb
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.lb.id]
  key_name               = local.key_name

  root_block_device {
    volume_size = var.root_volume_size
  }

  tags = {
    Name = "${var.project}-lb"
    Role = "loadbalancer"
  }
}

# ---- Applications (réparties sur les AZ) ----
resource "aws_instance" "app" {
  count                  = var.app_count
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type_app
  subnet_id              = aws_subnet.public[count.index % length(aws_subnet.public)].id
  vpc_security_group_ids = [aws_security_group.app.id]
  key_name               = local.key_name

  root_block_device {
    volume_size = var.root_volume_size
  }

  tags = {
    Name = "${var.project}-app-${count.index + 1}"
    Role = "app"
  }
}

# ---- Base de données ----
# Conserve une IP publique pour l'administration SSH par l'admin, mais le
# Security Group n'autorise PostgreSQL que depuis le SG app : la base n'est
# jamais joignable depuis Internet sur son port applicatif.
resource "aws_instance" "db" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type_db
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.db.id]
  key_name               = local.key_name
  iam_instance_profile   = aws_iam_instance_profile.db_backup.name

  root_block_device {
    volume_size = var.root_volume_size
  }

  tags = {
    Name = "${var.project}-db"
    Role = "db"
  }
}

# ---- Usine logicielle (bonus) ----
resource "aws_instance" "citools" {
  count                  = var.enable_citools ? 1 : 0
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type_citools
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.citools[0].id]
  key_name               = local.key_name

  root_block_device {
    volume_size = var.root_volume_size + 30 # SonarQube/Nexus consomment du disque
  }

  tags = {
    Name = "${var.project}-citools"
    Role = "citools"
  }
}
