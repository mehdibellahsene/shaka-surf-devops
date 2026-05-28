# Bucket S3 — stockage des backups de la base de données.
# Versioning + chiffrement au repos + blocage total des accès publics +
# lifecycle de rétention (7 jours sur le préfixe postgres/).

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "backups" {
  bucket = "${var.project}-backups-${random_id.bucket_suffix.hex}"

  tags = { Name = "${var.project}-backups" }
}

resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "backups" {
  bucket                  = aws_s3_bucket.backups.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    id     = "expire-postgres-dumps"
    status = "Enabled"

    filter {
      prefix = "postgres/"
    }

    # Rétention de 7 sauvegardes quotidiennes (justifiée dans le README).
    expiration {
      days = 7
    }

    # Nettoyage des versions non courantes laissées par le versioning.
    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}
