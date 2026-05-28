variable "region" {
  description = "Région AWS où déployer l'infrastructure."
  type        = string
  default     = "eu-west-3"
}

variable "project" {
  description = "Nom du projet, utilisé pour préfixer/étiqueter les ressources."
  type        = string
  default     = "shaka-surf"
}

variable "app_count" {
  description = "Nombre de VMs applicatives (exigence du sujet : >= 2)."
  type        = number
  default     = 2

  validation {
    condition     = var.app_count >= 2
    error_message = "Le sujet impose au moins 2 instances applicatives (app_count >= 2)."
  }
}

variable "enable_citools" {
  description = "Provisionner la VM usine logicielle (Jenkins/SonarQube/Nexus) — partie bonus."
  type        = bool
  default     = true
}

variable "vpc_cidr" {
  description = "Bloc CIDR du VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "instance_type_lb" {
  description = "Type d'instance pour le load balancer."
  type        = string
  default     = "t3.small"
}

variable "instance_type_app" {
  description = "Type d'instance pour les VMs applicatives."
  type        = string
  default     = "t3.medium"
}

variable "instance_type_db" {
  description = "Type d'instance pour la base de données."
  type        = string
  default     = "t3.medium"
}

variable "instance_type_citools" {
  description = "Type d'instance pour l'usine logicielle (SonarQube/Nexus sont gourmands)."
  type        = string
  default     = "t3.large"
}

variable "ssh_key_name" {
  description = "Nom de la paire de clés EC2 existante à associer aux instances."
  type        = string
}

variable "ssh_public_key_path" {
  description = "Chemin local vers la clé publique SSH (laisser vide pour réutiliser ssh_key_name déjà existante dans AWS)."
  type        = string
  default     = ""
}

variable "admin_cidr" {
  description = "CIDR autorisé à se connecter en SSH (et aux UIs de l'usine logicielle). Mettre votre IP publique /32 dans terraform.tfvars."
  type        = string

  # Pas de valeur par défaut : la variable est obligatoire, et 0.0.0.0/0 est
  # refusé (le SSH des VMs et les UIs citools ne doivent jamais être ouverts
  # à tout Internet — exigence « règles firewall adaptées » du sujet).
  validation {
    condition     = var.admin_cidr != "0.0.0.0/0"
    error_message = "admin_cidr ne doit pas être 0.0.0.0/0 : indiquez votre IP publique en /32 (ex. 203.0.113.10/32)."
  }
}

variable "root_volume_size" {
  description = "Taille (Go) du disque racine des instances."
  type        = number
  default     = 20
}

variable "ansible_ssh_user" {
  description = "Utilisateur SSH par défaut des AMIs Ubuntu (pour l'inventaire Ansible)."
  type        = string
  default     = "ubuntu"
}
