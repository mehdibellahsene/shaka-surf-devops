# Shaka Surf — Infrastructure DevOps

Déploiement **automatisé, multi-machines et reproductible** de l'application
[Shaka Surf](https://github.com/BMR-Consulting/Shaka-Surf) sur AWS, provisionné
avec **Terraform** (Infrastructure as Code) et configuré avec **Ansible** (rôles +
inventaire). Chaque rôle Ansible est couvert par un scénario **Molecule**.

> Projet DevOps — EFREI 4e année. Toute l'infrastructure est en code : aucune
> ressource n'est créée manuellement.

---

## 1. Architecture

```
Internet
   │ HTTPS (443) — Let's Encrypt via <ip-lb>.sslip.io
   ▼
[ VM Load Balancer (Nginx) ]   point d'entrée unique, terminaison TLS, round-robin
   ├──────────────┬──────────────┐
   ▼              ▼
[ VM App 1 ]   [ VM App N≥2 ]    docker compose : web + backend + auth + rest + kong
   │              │
   └──────┬───────┘
          ▼
[ VM Base de données ]           PostgreSQL 15, non exposée à Internet
          │ pg_dump quotidien chiffré
          ▼
[ Bucket S3 ]                    backups (versioning + lifecycle 7 jours)

[ VM Usine logicielle (citools) ]  Jenkins 8080 · SonarQube 9000 · Nexus 8081 (bonus)
```

Détails (machines, rôles, flux réseau, ports, Security Groups) :
[`docs/architecture.md`](docs/architecture.md).
Conception complète : [`docs/specs/`](docs/specs/).

### Application déployée

Shaka Surf est un SaaS multi-tenant dockerisé (Next.js + Fastify + Supabase :
GoTrue, PostgREST, Kong). La stack `docker-compose` d'origine est réutilisée sur
chaque VM App **sans son service `db`** : PostgreSQL est déporté sur la VM base de
données dédiée.

---

## 2. Pré-requis

Sur votre **poste de contrôle** (Linux, WSL ou macOS — Ansible ne tourne pas
nativement sous Windows) :

| Outil       | Version conseillée | Rôle |
|-------------|--------------------|------|
| Terraform   | ≥ 1.5              | Provisionnement AWS |
| Ansible     | ≥ 2.15             | Configuration des VMs |
| Molecule + Docker | dernières    | Tests des rôles |
| AWS CLI     | v2                 | Authentification AWS |
| Une paire de clés SSH EC2 | —    | Accès aux VMs |

- Un compte AWS et des credentials configurés (`aws configure` ou variables
  d'environnement `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`).
- Une paire de clés EC2 existante dans la région cible (ou fournir une clé
  publique locale via `ssh_public_key_path`).

Installer les collections Ansible :

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml
```

---

## 3. Déploiement de zéro

### Étape 1 — Provisionner l'infrastructure (Terraform)

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Éditer terraform.tfvars : ssh_key_name, admin_cidr (votre IP/32), région…

terraform init
terraform plan
terraform apply
```

À la fin, Terraform :
- crée le VPC, les Security Groups, les VMs (LB, ≥2 App, DB, citools), le bucket
  S3 et le rôle IAM ;
- **génère automatiquement** l'inventaire Ansible dans
  `ansible/inventory/hosts.ini` (depuis les outputs).

Récupérer l'URL publique : `terraform output lb_url`.

### Étape 2 — Renseigner les secrets (Ansible Vault)

```bash
cd ../ansible
cp group_vars/all/vault.example.yml group_vars/all/vault.yml
# Renseigner de vraies valeurs (mot de passe PostgreSQL, JWT, clés Supabase,
# passphrase de chiffrement des backups…)
ansible-vault encrypt group_vars/all/vault.yml
```

> `vault.yml` est **gitignoré** : il ne doit jamais être committé en clair.

### Étape 3 — Configurer et déployer (Ansible)

```bash
ansible-playbook site.yml --ask-vault-pass
```

L'ordre des plays garantit que la base est prête avant les apps, et que le load
balancer connaît les upstreams applicatifs.

### Étape 4 — Vérifier

```bash
curl -I "$(cd ../terraform && terraform output -raw lb_url)"
```

---

## 4. Tests Molecule

Chaque rôle possède un scénario Molecule (driver Docker) qui vérifie que le
service est actif et que les ports attendus répondent.

Depuis un poste avec Docker :

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml

# Un rôle :
cd roles/database && molecule test

# Tous les rôles :
for r in common database app loadbalancer backup jenkins sonarqube nexus; do
  (cd roles/$r && molecule test) || break
done
```

> Note : pour `app`, `sonarqube` et `nexus`, Molecule valide le rendu des
> templates et la configuration (le boot complet en docker-in-docker serait trop
> lourd) ; pour `common`, `database`, `loadbalancer`, `backup` et `jenkins`, le
> service réel est démarré et testé.

---

## 5. Stratégie de backup

| Paramètre     | Valeur | Justification |
|---------------|--------|---------------|
| **Quoi**      | `pg_dump` de la base applicative | Dump logique portable (schéma + données), restaurable sur n'importe quelle instance PostgreSQL 15. |
| **Quand**     | Quotidien à 02:00 (cron) | Trafic faible la nuit ; RPO ≤ 24 h, suffisant pour un SaaS au volume modéré, sans surcoût de stockage/CPU. |
| **Traitement**| gzip + chiffrement AES-256 (openssl, passphrase Vault) | Compression pour réduire le coût S3 ; chiffrement pour la confidentialité au transit et au repos. |
| **Où**        | `s3://<bucket>/postgres/AAAA-MM-JJ_HHMMSS.sql.gz.enc` | Bucket dédié, versioning + SSE activés, accès public bloqué. |
| **Rétention** | 7 sauvegardes quotidiennes (lifecycle S3) | Couvre une semaine de récupération ; au-delà, suppression automatique pour maîtriser les coûts. Purge locale immédiate après upload. |
| **Accès S3**  | Instance-profile IAM (VM DB) | Aucune clé statique : permissions limitées au préfixe `postgres/` du seul bucket. |

Le script de backup est déployé en `/usr/local/bin/pg_backup.sh` par le rôle
`backup`.

---

## 6. Restauration depuis S3

Le playbook `restore.yml` est **indépendant** du playbook principal. Il récupère
le **dernier** dump présent dans le bucket, le déchiffre et le restaure sur la VM
base de données.

```bash
cd ansible
ansible-playbook restore.yml --ask-vault-pass
```

Sous le capot, il exécute `/usr/local/bin/pg_restore.sh` qui :
1. liste `s3://<bucket>/postgres/` et sélectionne l'objet le plus récent,
2. le télécharge, le déchiffre (passphrase Vault) et le décompresse,
3. le réinjecte via `psql`.

---

## 7. Sécurité

- **Aucune credential en clair** dans le dépôt. Secrets gérés par **Ansible
  Vault** (`vault.yml` chiffré et gitignoré ; seul `vault.example.yml` est versionné).
- `.gitignore` exclut `*.tfstate*`, `*.tfvars`, `.env`, `*.pem`/`*.key`,
  l'inventaire généré et `vault.yml`.
- **Security Groups** stricts par rôle ; le load balancer ne peut pas joindre la
  base de données ; la base n'expose jamais son port 5432 à Internet.
- Accès SSH restreint à `admin_cidr` (votre IP en /32 — à régler dans `terraform.tfvars`).
- Accès S3 via **instance-profile IAM** (pas de clé statique).
- Durcissement SSH (root et mots de passe désactivés) + fail2ban via le rôle `common`.

---

## 8. Structure du dépôt

```
shaka-surf-devops/
├── README.md
├── .gitignore
├── docs/
│   ├── architecture.md            # schéma, rôles, flux réseau, ports
│   └── specs/                     # conception détaillée
├── terraform/                     # provisionnement AWS (IaC)
│   ├── providers.tf  variables.tf  outputs.tf
│   ├── network.tf  security.tf  compute.tf  s3.tf  iam.tf
│   ├── terraform.tfvars.example
│   └── templates/inventory.tmpl   # génère l'inventaire Ansible
└── ansible/
    ├── ansible.cfg  requirements.yml
    ├── inventory/hosts.ini        # généré par Terraform (gitignoré)
    ├── group_vars/all/{vars.yml, vault.example.yml}
    ├── site.yml  restore.yml
    └── roles/
        ├── common/ database/ app/ loadbalancer/ backup/
        └── jenkins/ sonarqube/ nexus/   (bonus — usine logicielle)
            # chaque rôle : tasks/ defaults/ handlers/ templates/
            #               molecule/default/{molecule,converge,verify}.yml
```

---

## 9. Limites connues

- `terraform apply` nécessite des credentials AWS (coûts à votre charge).
- Le nœud de contrôle doit être sous Linux/WSL/macOS (Ansible/Molecule).
- Le déploiement réel n'a pas été exécuté ici (pas de compte cloud fourni) ; le
  code est écrit pour être appliqué tel quel.
