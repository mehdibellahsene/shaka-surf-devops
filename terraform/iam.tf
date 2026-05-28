# IAM — la VM base de données écrit/lit ses backups dans S3 via un
# instance-profile (aucune clé statique committée).

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "db_backup" {
  name               = "${var.project}-db-backup"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

data "aws_iam_policy_document" "db_backup" {
  # Lister le bucket (nécessaire pour retrouver le dernier dump au restore).
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.backups.arn]
  }

  # Écrire / lire / supprimer uniquement sous le préfixe postgres/.
  statement {
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
    ]
    resources = ["${aws_s3_bucket.backups.arn}/postgres/*"]
  }
}

resource "aws_iam_role_policy" "db_backup" {
  name   = "${var.project}-db-backup-s3"
  role   = aws_iam_role.db_backup.id
  policy = data.aws_iam_policy_document.db_backup.json
}

resource "aws_iam_instance_profile" "db_backup" {
  name = "${var.project}-db-backup"
  role = aws_iam_role.db_backup.name
}
