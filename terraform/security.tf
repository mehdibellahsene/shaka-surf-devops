# ============================================================================
# Security Groups — une politique par type de machine.
# Principe : surface minimale. Le LB ne peut PAS joindre la base de données.
# ============================================================================

# ---- Load balancer : seul point d'entrée Internet (80/443) ----
resource "aws_security_group" "lb" {
  name        = "${var.project}-sg-lb"
  description = "Load balancer : HTTP/HTTPS public, SSH admin."
  vpc_id      = aws_vpc.main.id

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
    description = "SSH admin"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-sg-lb" }
}

# ---- Applications : joignables seulement par le LB (port 80) ----
resource "aws_security_group" "app" {
  name        = "${var.project}-sg-app"
  description = "VMs applicatives : HTTP depuis le LB uniquement, SSH admin."
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP frontend depuis le load balancer"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.lb.id]
  }

  ingress {
    description = "SSH admin"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-sg-app" }
}

# ---- Base de données : PostgreSQL depuis les apps uniquement, jamais Internet ----
resource "aws_security_group" "db" {
  name        = "${var.project}-sg-db"
  description = "Base de donnees : PostgreSQL depuis le SG app uniquement, SSH admin."
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL depuis les VMs applicatives"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  ingress {
    description = "SSH admin"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-sg-db" }
}

# ---- Usine logicielle : isolée, UIs accessibles à l'admin uniquement ----
resource "aws_security_group" "citools" {
  count       = var.enable_citools ? 1 : 0
  name        = "${var.project}-sg-citools"
  description = "Usine logicielle : Jenkins/SonarQube/Nexus, acces admin uniquement."
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS (vhosts Jenkins/SonarQube/Nexus)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  ingress {
    description = "Jenkins"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  ingress {
    description = "SonarQube"
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  ingress {
    description = "Nexus"
    from_port   = 8081
    to_port     = 8081
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  ingress {
    description = "SSH admin"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-sg-citools" }
}
