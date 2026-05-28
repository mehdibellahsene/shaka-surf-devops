# Conception — Infrastructure DevOps pour Shaka Surf

> **Document historique.** L'application réelle (stack Supabase) décrite ici a
> depuis été remplacée par le mock versionné dans `app/` (le sujet laisse les
> technologies applicatives libres). L'architecture d'infrastructure reste
> identique ; pour l'état actuel, voir `README.md` et `docs/architecture.md`.

> Spec de conception du projet DevOps (EFREI 4e année). Déploiement automatisé,
> multi-machines, de l'application **Shaka Surf** sur AWS via Terraform + Ansible,
> testé avec Molecule.

## 1. Objectif

Provisionner et configurer, **entièrement en Infrastructure as Code**, une
infrastructure multi-VM qui héberge l'application Shaka Surf, conforme au schéma
imposé : Load Balancer → N≥2 VMs applicatives → VM base de données dédiée (non
exposée) → bucket S3 pour les backups. Plus une VM « usine logicielle » (bonus)
hébergeant Jenkins, SonarQube et Nexus.

L'environnement doit être **reproductible de zéro** par un tiers à partir du
dépôt seul.

## 2. Application déployée — Shaka Surf

SaaS multi-tenant dockerisé (monorepo `BMR-Consulting/Shaka-Surf`) :

| Service          | Image / techno              | Port interne | Rôle |
|------------------|-----------------------------|--------------|------|
| `web`            | Next.js 16 (build standalone)| 3000         | Frontend |
| `backend`        | Fastify (Node)              | 9940         | API métier, détient les secrets |
| `auth`           | supabase/gotrue             | 9999         | Authentification JWT |
| `rest`           | postgrest/postgrest         | 3000 (int.)  | API REST auto-générée |
| `kong`           | kong:2.8.1                  | 8000/8443    | API gateway (`/auth`, `/rest`) |
| `meta` + `studio`| supabase                    | 8080 / 3000  | Admin DB (optionnel en prod) |
| `mailer-templates`| nginx:alpine               | 80           | Templates e-mail HTML |
| `db`             | postgres:15                 | 5432         | **Déplacé sur la VM DB dédiée** |

Constat clé : l'app est **déjà orchestrée par `docker-compose`**. La stratégie de
déploiement réutilise ce compose, en **retirant le service `db`** (qui part sur la
VM dédiée) et en injectant la configuration via un template Ansible.

## 3. Architecture cible

```
Internet
   │ HTTPS (443) — Let's Encrypt, domaine <ip>.sslip.io
   ▼
┌─────────────────────────┐
│  VM Load Balancer (Nginx)│  IP publique, terminaison TLS, round-robin
└─────────────────────────┘
   │ HTTP (80) interne vers le frontend des VMs App
   ├───────────────────────────┬───────────────────────────┐
   ▼                           ▼
┌──────────────┐          ┌──────────────┐
│  VM App 1    │   ...    │  VM App N≥2  │  docker-compose : web+backend+auth+
│  (privée*)   │          │  (privée*)   │  rest+kong+mailer-templates
└──────────────┘          └──────────────┘
   │ PostgreSQL (5432), restreint au SG App uniquement
   └─────────────┬─────────────┘
                 ▼
        ┌──────────────────┐
        │  VM Base données │  PostgreSQL 15, **pas d'IP publique**
        │  (privée)        │  init Supabase + RLS
        └──────────────────┘
                 │ pg_dump quotidien (chiffré, compressé)
                 ▼
          ┌──────────────┐
          │  Bucket S3   │  versioning + chiffrement + lifecycle 7 j
          └──────────────┘

  ┌───────────────────────────────┐
  │  VM Usine logicielle (citools) │  isolée du réseau applicatif (bonus)
  │  Jenkins :8080 · SonarQube     │  chacun en HTTPS via sous-domaine sslip.io
  │  :9000 · Nexus :8081           │
  └───────────────────────────────┘
```

\* Les VMs App peuvent être en subnet public avec SG restrictif (seul le LB
atteint le port 80) **ou** en subnet privé derrière le LB. Choix retenu : subnet
public + SG strict (plus simple, pas de NAT Gateway à provisionner ; le port
applicatif n'accepte que la source = SG du LB).

### Flux réseau / Security Groups

| Groupe        | Entrant autorisé                                   | Sortant |
|---------------|----------------------------------------------------|---------|
| LB            | 80, 443 depuis 0.0.0.0/0 ; 22 depuis IP admin      | tout    |
| App           | 80 depuis SG-LB uniquement ; 22 depuis IP admin    | tout    |
| DB            | 5432 depuis SG-App uniquement ; 22 depuis IP admin | tout    |
| citools       | 8080/9000/8081 + 443 depuis IP admin ; 22 idem     | tout    |

Le LB **ne connaît pas** la VM DB (aucune règle entre les deux) — exigence du sujet.

## 4. Composant Terraform (`terraform/`)

Provisionne **exclusivement** :

- **Réseau** : 1 VPC, subnets publics multi-AZ, Internet Gateway, route tables.
- **Compute** : `aws_instance` pour LB (1), App (`count = var.app_count`, ≥2), DB (1),
  citools (1). AMI Ubuntu LTS, clé SSH gérée par variable.
- **Load balancer** : VM Nginx dédiée (pas d'ALB managé) pour maîtriser la
  terminaison TLS Let's Encrypt + sslip.io.
- **Stockage** : 1 `aws_s3_bucket` backups (versioning, SSE, `lifecycle` 7 jours,
  blocage accès public).
- **IAM** : rôle/instance-profile permettant à la VM DB d'écrire dans le bucket
  (pas de clé statique commitée).
- **Security Groups** : un par rôle, règles du tableau ci-dessus.
- **Outputs** : IP publiques/privées de chaque VM, nom du bucket → consommés pour
  générer l'inventaire Ansible.

Contraintes :
- `terraform.tfstate*` **gitignorés** (peut contenir des secrets).
- Aucune ressource créée à la main.
- Variables sensibles via `terraform.tfvars` (gitignoré) ou variables d'env.
- Backend state local documenté ; migration vers backend distant mentionnée dans le README.

### Génération de l'inventaire Ansible

Un template `terraform/templates/inventory.tmpl` + une ressource `local_file`
(ou `terraform output -json` + script) écrit `ansible/inventory/hosts.ini` avec
les groupes `loadbalancer`, `app`, `db`, `citools` peuplés depuis les outputs.

## 5. Composant Ansible (`ansible/`)

Inventaire par groupes ; secrets via **Ansible Vault** (`group_vars/all/vault.yml`).

### Rôles

| Rôle          | Responsabilité |
|---------------|----------------|
| `common`      | MAJ paquets, utilisateur deploy, durcissement SSH, install Docker + plugin compose, fail2ban |
| `loadbalancer`| Nginx reverse-proxy, upstream = VMs App, certbot Let's Encrypt (sslip.io), redirection 80→443 |
| `app`         | Clone/copie Shaka Surf, dépose `docker-compose.yml` (sans `db`) + `.env` templé depuis Vault, `docker compose up -d`, pointe la DB vers la VM DB |
| `database`    | Install PostgreSQL 15, applique les scripts d'init Supabase (`volumes/db/init/*.sql`), crée rôles/extensions, `pg_hba.conf` restreint au subnet App |
| `backup`      | Script `pg_dump` chiffré + cron quotidien, upload S3 via AWS CLI (credentials par instance-profile), purge locale |
| `jenkins`     | Install Jenkins, service démarré, accès initial sécurisé, vhost HTTPS |
| `sonarqube`   | Install SonarQube, config de base, connectivité vérifiée, vhost HTTPS |
| `nexus`       | Install Nexus, service démarré, repo par défaut accessible, vhost HTTPS |

### Playbooks

- `site.yml` — orchestre tous les rôles par groupe.
- `restore.yml` — **indépendant** : récupère le dernier dump depuis S3 et le
  restaure sur la VM DB. Documenté dans le README.

## 6. Tests — Molecule

Un scénario par rôle (driver **Docker**). Chaque scénario :
- converge le rôle dans un conteneur,
- vérifie (idempotence + `verify.yml`) que le service attendu est **actif** et que
  le **port attendu répond**.

`molecule test` doit passer sans erreur sur l'ensemble des rôles. Lancé depuis un
nœud de contrôle Linux/WSL/macOS avec Docker.

## 7. Stratégie de backup (justifiée)

- **Quoi** : `pg_dump` de la base applicative (schéma + données).
- **Fréquence** : quotidienne à 02:00 (cron) — compromis fraîcheur/coût pour un
  SaaS au trafic modéré ; RPO ≤ 24 h.
- **Traitement** : compression gzip + chiffrement (clé via Vault) avant upload.
- **Destination** : bucket S3 dédié (`s3://<bucket>/postgres/AAAA-MM-JJ.sql.gz.enc`).
- **Rétention** : 7 sauvegardes quotidiennes via **lifecycle S3** (suppression
  auto au-delà) + purge locale immédiate après upload réussi.
- **Restauration** : `ansible-playbook restore.yml` télécharge le dernier objet,
  déchiffre, `psql` restore. Procédure pas-à-pas dans le README.

## 8. Sécurité / secrets

- Aucune credential en clair commitée (pénalité automatique sinon).
- Ansible Vault pour mots de passe DB, JWT_SECRET, clés Supabase, etc.
  (`vault.example.yml` versionné, `vault.yml` gitignoré ou chiffré).
- `.gitignore` couvre : `*.tfstate*`, `.terraform/`, `*.tfvars`, `.env`,
  `*.pem`, `*.key`, `vault.yml` non chiffré, caches Molecule.
- Accès S3 par **instance-profile IAM**, pas de clé statique.
- DB sans IP publique ; SSH limité à une IP admin paramétrable.

## 9. Documentation (`README.md`)

- Description du projet + schéma d'architecture (machines, rôles, flux, ports).
- Prérequis (compte AWS, Terraform, Ansible, Docker, clé SSH).
- Déploiement de zéro, étape par étape (terraform → inventaire → ansible).
- Stratégie de backup (fréquence, rétention, localisation) + justification.
- Lancement des tests Molecule.
- Procédure de restauration depuis S3.

## 10. Structure du dépôt

```
shaka-surf-devops/
├── README.md
├── .gitignore
├── docs/
│   ├── specs/2026-05-27-shaka-surf-devops-design.md
│   └── architecture.md
├── terraform/
│   ├── main.tf  providers.tf  variables.tf  outputs.tf
│   ├── network.tf  compute.tf  security.tf  s3.tf  iam.tf
│   ├── terraform.tfvars.example
│   └── templates/inventory.tmpl
└── ansible/
    ├── ansible.cfg
    ├── inventory/hosts.ini   (généré)
    ├── group_vars/all/{vars.yml, vault.example.yml}
    ├── site.yml  restore.yml
    └── roles/
        ├── common/  loadbalancer/  app/  database/  backup/
        └── jenkins/  sonarqube/  nexus/
            └── (chacun avec tasks/, defaults/, handlers/, templates/,
                 molecule/default/{molecule.yml,converge.yml,verify.yml})
```

## 11. Limites connues

- Le déploiement réel (`terraform apply`) nécessite des credentials AWS (non
  fournis ici) ; le code est écrit pour être appliqué tel quel.
- `molecule test` requiert Docker + un nœud de contrôle Linux/WSL/macOS.
- L'environnement de développement local est Windows : le code est produit et
  validé statiquement ; l'exécution se fait côté utilisateur.

## 12. Livrable

Dépôt public **`mehdibellahsene/shaka-surf-devops`** contenant l'ensemble
ci-dessus, avec un historique de commits clair.
