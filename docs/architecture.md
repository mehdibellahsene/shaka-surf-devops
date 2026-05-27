# Architecture

## Vue d'ensemble

```
Internet
   │ HTTPS (443) — Let's Encrypt, domaine <ip-lb>.sslip.io
   ▼
┌──────────────────────────┐
│  VM Load Balancer (Nginx) │  IP publique · terminaison TLS · round-robin
└──────────────────────────┘
   │ HTTP (80) interne → frontend des VMs App (port 3000)
   ├───────────────────────────┬───────────────────────────┐
   ▼                           ▼
┌──────────────┐          ┌──────────────┐
│  VM App 1    │   ...    │  VM App N≥2  │  docker compose : web + backend +
│              │          │              │  auth + rest + kong + mailer-templates
└──────────────┘          └──────────────┘
   │ PostgreSQL (5432) — autorisé au seul Security Group App
   └─────────────┬─────────────┘
                 ▼
        ┌──────────────────┐
        │  VM Base données │  PostgreSQL 15 · init Supabase + RLS
        │                  │  PAS exposée sur Internet (pas d'IP entrante publique applicative)
        └──────────────────┘
                 │ pg_dump quotidien (gzip + chiffré)
                 ▼
          ┌──────────────┐
          │  Bucket S3   │  versioning + SSE + lifecycle 7 jours
          └──────────────┘

  ┌────────────────────────────────┐
  │  VM Usine logicielle (citools)  │  isolée du réseau applicatif (bonus)
  │  Jenkins :8080 · SonarQube :9000 │  chacun en HTTPS via sous-domaine sslip.io
  │  · Nexus :8081                  │
  └────────────────────────────────┘
```

## Machines et rôles Ansible

| Hôte (groupe inventaire) | Rôles appliqués                     | Ports exposés |
|--------------------------|-------------------------------------|---------------|
| `loadbalancer`           | common, loadbalancer                | 22, 80, 443   |
| `app` (×N≥2)             | common, app                         | 22, 80 (depuis LB) |
| `db`                     | common, database, backup            | 22, 5432 (depuis App) |
| `citools`                | common, jenkins, sonarqube, nexus   | 22, 443, 8080, 9000, 8081 |

## Flux réseau / Security Groups

| Security Group | Entrant autorisé                                       | But |
|----------------|--------------------------------------------------------|-----|
| `sg-lb`        | 80, 443 depuis `0.0.0.0/0` ; 22 depuis `admin_cidr`    | Point d'entrée HTTPS unique |
| `sg-app`       | 80 depuis `sg-lb` uniquement ; 22 depuis `admin_cidr`  | App joignable seulement via le LB |
| `sg-db`        | 5432 depuis `sg-app` uniquement ; 22 depuis `admin_cidr` | DB non exposée à Internet |
| `sg-citools`   | 8080/9000/8081/443 + 22 depuis `admin_cidr`            | Usine logicielle isolée |

> **Important :** aucune règle n'autorise le Load Balancer à joindre la VM Base de
> données — le LB ne connaît pas la BDD (exigence du sujet, conseil §6).

## Composants

- **Terraform** (`terraform/`) : VPC + subnets, Security Groups, EC2 (LB/App/DB/citools),
  bucket S3, rôle IAM (instance-profile) pour les backups, outputs → inventaire Ansible.
- **Ansible** (`ansible/`) : rôles + inventaire par groupes, secrets via Ansible Vault,
  playbooks `site.yml` (déploiement) et `restore.yml` (restauration S3 indépendante).
- **Molecule** : un scénario par rôle (driver Docker), vérifie service actif + ports.
