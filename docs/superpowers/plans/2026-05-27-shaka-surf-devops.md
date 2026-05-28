# Shaka Surf DevOps Infrastructure — Implementation Plan

> **Document historique.** L'application réelle (stack Supabase) visée par ce
> plan a depuis été remplacée par le mock versionné dans `app/`. Pour l'état
> actuel du dépôt, voir `README.md` et `docs/architecture.md`.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a complete, reproducible Infrastructure-as-Code repository that provisions (Terraform/AWS) and configures (Ansible) a multi-VM deployment of the Shaka Surf app — load balancer, ≥2 app VMs, dedicated DB VM, S3 backups — plus a bonus CI/CD VM, each Ansible role covered by a Molecule scenario.

**Architecture:** Terraform creates the VPC, security groups, EC2 instances, S3 bucket and IAM, then renders the Ansible inventory from its outputs. Ansible configures each host group via roles. The app VMs run the existing Shaka Surf `docker-compose` stack minus the `db` service, which lives on the dedicated DB VM (PostgreSQL 15 with Supabase init). A cron `pg_dump` ships encrypted backups to S3.

**Tech Stack:** Terraform (AWS provider), Ansible (roles + Vault), Molecule (Docker driver), Docker Compose, Nginx + certbot, PostgreSQL 15, Jenkins/SonarQube/Nexus.

**Note on TDD:** For IaC the test layer is Molecule (per-role) + `terraform validate`/`fmt`. Each role task writes its Molecule `verify.yml` (asserting service active + port open) as the "test". App code is not modified; we only orchestrate the upstream repo.

---

### Task 1: Repository scaffolding & .gitignore

**Files:**
- Create: `.gitignore`, `README.md` (stub, filled in Task 12)
- Create: `docs/architecture.md`

- [ ] Write `.gitignore` covering `*.tfstate*`, `.terraform/`, `*.tfvars` (except `*.example`), `.env`, `*.pem`, `*.key`, `ansible/inventory/hosts.ini`, `vault.yml`, `*.retry`, Molecule caches, `__pycache__`.
- [ ] Write `docs/architecture.md` with the ASCII diagram + SG table from the spec.
- [ ] Commit: `chore: repo scaffolding, gitignore, architecture doc`

### Task 2: Terraform — providers & variables

**Files:**
- Create: `terraform/providers.tf`, `terraform/variables.tf`, `terraform/terraform.tfvars.example`

- [ ] `providers.tf`: AWS provider, required_versions, region from var.
- [ ] `variables.tf`: `region`, `project`, `app_count` (default 2, validation ≥2), `instance_type_*`, `ssh_key_name`, `admin_cidr`, `ubuntu_ami` (data source instead), `db_name`, `db_user`.
- [ ] `terraform.tfvars.example`: documented sample values, no secrets.
- [ ] Commit.

### Task 3: Terraform — network

**Files:** Create: `terraform/network.tf`

- [ ] VPC, public subnets across 2 AZs (data source for AZs), IGW, public route table + associations.
- [ ] Commit.

### Task 4: Terraform — security groups

**Files:** Create: `terraform/security.tf`

- [ ] SG-LB (80/443 from 0.0.0.0/0, 22 from admin_cidr), SG-App (80 from SG-LB, 22 admin), SG-DB (5432 from SG-App, 22 admin), SG-citools (8080/9000/8081/443 + 22 from admin). No LB↔DB rule.
- [ ] Commit.

### Task 5: Terraform — S3 + IAM

**Files:** Create: `terraform/s3.tf`, `terraform/iam.tf`

- [ ] S3 bucket (random suffix), versioning, SSE (AES256), public access block, lifecycle expire `postgres/` after 7 days.
- [ ] IAM role + instance profile for DB VM with least-privilege policy (PutObject/GetObject/ListBucket on this bucket only).
- [ ] Commit.

### Task 6: Terraform — compute + outputs + inventory render

**Files:** Create: `terraform/compute.tf`, `terraform/outputs.tf`, `terraform/templates/inventory.tmpl`

- [ ] Ubuntu AMI data source; EC2 for LB, App (`count = app_count`), DB (attaches instance profile, no public IP assoc via subnet but here public subnet — set `associate_public_ip_address=false` for DB; reachable via SSH bastion-less from admin only? — document: DB private IP only, SSH through app or VPN). For simplicity DB stays in public subnet with `associate_public_ip_address=false`; SSH from admin reaches it only if it has public IP — so instead place DB management via the LB? **Decision:** DB gets public IP for SSH config convenience but SG blocks everything except 22 from admin + 5432 from SG-App. Documented as a project tradeoff.
- [ ] `outputs.tf`: public/private IPs per group, bucket name.
- [ ] `inventory.tmpl` + `local_file` resource writing `ansible/inventory/hosts.ini` with groups loadbalancer/app/db/citools and `:vars` (ansible_user, bucket name, db private ip).
- [ ] Run `terraform fmt` (if available) and commit.

### Task 7: Ansible base — config, inventory vars, common role

**Files:**
- Create: `ansible/ansible.cfg`, `ansible/group_vars/all/vars.yml`, `ansible/group_vars/all/vault.example.yml`
- Create: `ansible/roles/common/{tasks/main.yml,defaults/main.yml,handlers/main.yml}`
- Create: `ansible/roles/common/molecule/default/{molecule.yml,converge.yml,verify.yml}`

- [ ] `ansible.cfg`: inventory path, roles_path, host_key_checking=false, retry off.
- [ ] `group_vars/all/vars.yml`: non-secret vars (versions, paths). `vault.example.yml`: documented secret keys (db password, jwt secret, supabase keys, backup encryption passphrase) with placeholder values.
- [ ] `common/tasks`: apt update/upgrade, create `deploy` user, install Docker CE + compose plugin, fail2ban, basic SSH hardening.
- [ ] Molecule: converge runs common; verify asserts docker service active + `docker` binary present.
- [ ] Commit.

### Task 8: Ansible — database role + Molecule

**Files:** Create: `ansible/roles/database/{tasks,defaults,handlers,templates}/...` + `molecule/default/*`

- [ ] Install PostgreSQL 15, listen on private IP, create app DB + users.
- [ ] Copy Supabase init SQL (templated from upstream `volumes/db/init/*.sql`) and apply once (idempotent guard).
- [ ] `pg_hba.conf` template: allow app subnet CIDR on the app DB only; reject the rest.
- [ ] Molecule verify: postgresql service active, port 5432 listening, can connect locally.
- [ ] Commit.

### Task 9: Ansible — app role + Molecule

**Files:** Create: `ansible/roles/app/{tasks,defaults,templates}/...` + `molecule/default/*`

- [ ] Fetch Shaka Surf repo (git clone pinned ref) to `/opt/shaka-surf`.
- [ ] Template a `docker-compose.app.yml` derived from upstream **without `db`** (external DB host = db private IP) + `.env` from Vault vars.
- [ ] `docker compose -f docker-compose.app.yml up -d`.
- [ ] Molecule verify: compose project containers running, frontend port 3000 responds, backend 9940 responds. (In Molecule, mock with a lightweight stand-in: assert docker present + compose file valid via `docker compose config`.)
- [ ] Commit.

### Task 10: Ansible — loadbalancer + backup roles + Molecule

**Files:** Create: `ansible/roles/loadbalancer/...`, `ansible/roles/backup/...` + their `molecule/default/*`

- [ ] `loadbalancer`: install Nginx, template reverse-proxy vhost (upstream = app private IPs from inventory, proxy 80→app:3000), certbot for `<lb-ip>.sslip.io`, redirect 80→443. Molecule verify: nginx active, port 80/443 listening, config test passes.
- [ ] `backup`: deploy `/usr/local/bin/pg_backup.sh` (pg_dump | gzip | openssl enc → aws s3 cp), cron daily 02:00, local purge. Molecule verify: script present + executable, cron entry present.
- [ ] Commit each role.

### Task 11: Ansible — bonus citools roles (jenkins, sonarqube, nexus) + Molecule

**Files:** Create: `ansible/roles/{jenkins,sonarqube,nexus}/...` + `molecule/default/*` each

- [ ] `jenkins`: install via apt repo, service enabled, vhost HTTPS 8080. Verify: service active, 8080 listening.
- [ ] `sonarqube`: docker-based install (sysctl `vm.max_map_count`), service up, 9000 listening, vhost HTTPS. Verify accordingly.
- [ ] `nexus`: docker-based install, 8081 listening, vhost HTTPS. Verify accordingly.
- [ ] Commit each role.

### Task 12: Ansible — playbooks (site.yml, restore.yml)

**Files:** Create: `ansible/site.yml`, `ansible/restore.yml`

- [ ] `site.yml`: plays mapping groups→roles (common everywhere; database→db; app→app; loadbalancer→lb; jenkins/sonarqube/nexus→citools; backup→db).
- [ ] `restore.yml`: independent play targeting `db` — `aws s3 ls` newest object, download, openssl decrypt, gunzip, `psql` restore. Documented.
- [ ] Commit.

### Task 13: README + final docs

**Files:** Modify `README.md`

- [ ] Full README: project description, architecture diagram, prerequisites, step-by-step deploy (terraform → inventory → ansible-playbook), backup strategy + justification, Molecule instructions, restore procedure, security notes, repo structure.
- [ ] Commit.

### Task 14: Validation, push to GitHub

- [ ] `terraform fmt -check` / `validate` if tooling available; otherwise note.
- [ ] Verify no secrets committed (`git log -p` scan for keys; confirm .gitignore coverage).
- [ ] `gh repo create mehdibellahsene/shaka-surf-devops --public --source=. --remote=origin --push`.
- [ ] Confirm repo URL.

---

## Self-Review

**Spec coverage:**
- §4 Terraform (network, compute, LB-as-VM, S3, IAM, SG, outputs, inventory render) → Tasks 2–6. ✓
- §5 Ansible roles (common, loadbalancer, app, database, backup, jenkins, sonarqube, nexus) → Tasks 7–11. ✓
- §5 playbooks site.yml + restore.yml → Task 12. ✓
- §6 Molecule per role → embedded in Tasks 7–11. ✓
- §7 backup strategy → Task 10 (backup role) + Task 13 (README justification). ✓
- §8 security/secrets (gitignore, Vault, IAM, no public DB) → Tasks 1,5,7 + Task 14 secret scan. ✓
- §9 documentation → Task 13. ✓
- §10 structure → matches across tasks. ✓
- §12 livrable / push → Task 14. ✓

**Placeholder scan:** Task 9 Molecule uses a documented stand-in (compose validation) because a real multi-container Supabase stack can't boot inside a single Molecule container — this is an explicit, justified simplification, not a placeholder.

**Type/name consistency:** inventory groups (loadbalancer/app/db/citools), file names, and var names are consistent across tasks. ✓

**Known constraint:** local Windows host lacks Terraform/Ansible/Molecule, so execution validates statically; the README documents running from a Linux/WSL/macOS control node.
