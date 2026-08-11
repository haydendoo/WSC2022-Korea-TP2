# Unicorn GameDay - WSC2022 TP53 Day 2 Practice Starter Kit

This repository recreates the **starting state** participants received for
WorldSkills 2022 Test Project 53, Day 2 ("Micro Services On AWS EKS") -
see [`WSC2022SE_TP53_Day2_actual_en.pdf`](./WSC2022SE_TP53_Day2_actual_en.pdf)
for the original specification.

It is a practice environment generator, not a solution. Running the
Terraform here reproduces what a competitor's AWS account looked like
2 hours before requests started - baseline IAM and a bastion host - and
nothing more. Everything from "design the VPC" onward is the actual Day 2
challenge and is intentionally left undone.

## What this repository answers - and what it doesn't

> "What did the participant receive when the competition started?"

It does **not** answer "how should the participant solve Day 2?" The
architecture diagram in the spec (root/stub on EKS, backed by Redis,
MySQL/RDS, EFS, and S3) is one possible design, not a prescription - keep
your own architecture decisions open.

## Repository layout

```
├── terraform/          baseline IAM + bastion EC2 (see scope below)
├── services/
│   ├── root/            practice-compatible "root" binary (Go source + Dockerfile)
│   └── stub/             practice-compatible "stub" binary (Go source + Dockerfile)
├── database/
│   └── schema.sql        unicorndb / unicorns table, per the spec
├── config/               example + local-dev config JSON for both services
├── scripts/
│   ├── build.sh            compile root/stub for linux/amd64
│   ├── package.sh           assemble dist/ (see below) + optional Docker images
│   ├── verify.sh             smoke-test the built binaries (--help, GET /)
│   └── refund-notifier.sh    Request Exception Handling - see below
├── docker/
│   └── docker-compose.yaml  local practice stack (NOT the competition architecture)
└── dist/                 generated: the package handed to participants
    (run `./scripts/package.sh` to (re)build it - binaries, example
    configs, schema.sql, refund-notifier.sh, and dist/README.md)
```

## Terraform scope

### Provisioned (the baseline participants start with)

| Resource | Spec basis |
|---|---|
| `UnicornPolicy`, `AutoScalerPolicy`, `ELBControllerPolicy`, `EFSPolicy` | "The company security team has created several policies..." (Background) |
| `EKSClusterRole`, `EKSNodeRole` | "...two IAM roles named EKSClusterRole and EKSNodeRole have been created for you..." (Tasks §8) |
| `TeamRoleInstanceProfile` | "There is an EC2 instance profile ready for you to use... named like *TeamRoleInstanceProfile*" (Caution) |
| Bastion EC2 (Amazon Linux, SSM-only access) | "there is a running Amazon EC2 instance in the account... act as a bastion server" (Initial state / Caution) |
| Minimal VPC/subnet/IGW for the bastion (optional, `create_baseline_network`) | Only enough networking to make the bastion reachable - not the participant's VPC design |

The 4 security-team policies are created but deliberately **not attached**
to any role. Per the spec, the security team "[doesn't] leave any
document on this process, you need to figure out how to do it" - deciding
which roles need which policy (the EKS node role directly, or IRSA roles
you create for the load balancer controller / cluster autoscaler / EFS
CSI driver / the app itself) is part of the challenge.

`TeamRoleInstanceProfile`'s permissions are a documented, adjustable
policy (`terraform/iam.tf`, `TeamRoleBaselinePolicy`) - broad enough to
build the whole Day 2 solution from the bastion, but not
`AdministratorAccess`. Tune it via `variables.tf` or
`team_role_extra_managed_policy_arns`.

### NOT provisioned (the participant's Day 2 solution)

EKS cluster, node groups, RDS, ElastiCache, EFS, the application's S3
bucket, AWS AppConfig application, ALB, the AWS Load Balancer Controller,
Kubernetes Deployment/Service/Ingress/HPA, and any NAT/network
architecture beyond the bastion. Building these is the competition task -
see the Tasks section of the spec PDF.

## Deploying the baseline

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

Requires AWS credentials with permission to create IAM roles/policies,
an EC2 instance, and (if `create_baseline_network = true`, the default)
a small VPC. Review `variables.tf` first, especially `aws_region` and
`team_role_extra_managed_policy_arns`.

Connect to the bastion the way the spec requires - no SSH from the
internet, Session Manager only:

```bash
aws ssm start-session --target "$(terraform output -raw bastion_instance_id)"
```

(`terraform output bastion_connect_command` prints the full command.)

## The root / stub services

`services/root` and `services/stub` are **from-scratch practice
replacements** for the proprietary Go binaries described in the spec -
not the original binaries, and not a reverse-engineering of them. They
exist so you have something real to point your infrastructure at while
practicing, matching the documented interface:

- `--help`, `--port` (default `80`)
- `GET /` and `GET /healthz` return HTTP 200 (the spec's health check)
- Configuration is fetched from AWS AppConfig (`--appconfig-application` /
  `--appconfig-environment` / `--appconfig-profile`), matching "all
  unicorn applications need to communicate to AWS AppConfig Service in
  order to get configuration." A local JSON file (`--config`) is
  supported purely as a fallback for local testing - see
  `config/*.example.json` for the documented AppConfig payload shape and
  `config/*.local.json` for docker-compose.
- `root` additionally depends on Redis and an S3 bucket (refund records)
- `stub` additionally depends on Secrets Manager (rotated DB credentials)
  and MySQL/RDS (the `unicorns` table, see `database/schema.sql`)
- `GET /unicorns/{id}` demonstrates the cache-through path
  (Redis/MySQL -> filesystem -> generated) so you have a concrete way to
  test each dependency once it's wired up
- `POST /refund {"order":"<uuid>"}` writes a refund/exception record to
  S3, matching the "Request Exception Logs" flow in the spec's
  architecture diagram

Build and smoke-test both binaries:

```bash
./scripts/build.sh     # -> dist/root, dist/stub (linux/amd64)
./scripts/verify.sh     # --help + GET / checks
./scripts/package.sh     # tarball + (if Docker is available) local images
```

Try them locally, without touching AWS, via Docker Compose (Redis +
MySQL containers, S3/Secrets Manager left disabled - see the compose
file's header comment):

```bash
docker compose -f docker/docker-compose.yaml up --build
curl localhost:8080/            # root
curl localhost:8081/            # stub
```

## Request Exception Handling

Per the spec, refund/exception requests (a UUID) get written to your S3
bucket, and must be reported to the GameDay audit endpoint over HTTP POST.
`scripts/refund-notifier.sh` does this: it polls the bucket, reads the
UUID out of each new object's content, and POSTs
`{"id","order"}` to the audit endpoint, deduplicating against a
local state file so nothing is reported twice. `id` is your participant
ID, shown on your dashboard - it's how the audit endpoint knows which
participant to credit.

```bash
./scripts/refund-notifier.sh --bucket <your-bucket> --id <PARTICIPANT_ID> --endpoint <audit endpoint URL>
```

Run with `--help` for all options (custom endpoint, poll interval, state
file location, `--once` for a single pass, `--dry-run`). This script - or
one you write yourself the same shape - is the standalone tool the spec
mentions separately from the binaries: "There is also a script that can
be used, please refer to download link provided in Readme file".

## Participant workflow

```
Starter Terraform (this repo)
  ├── IAM policies (UnicornPolicy, AutoScalerPolicy, ELBControllerPolicy, EFSPolicy)
  ├── EKSClusterRole / EKSNodeRole
  ├── TeamRoleInstanceProfile
  └── Bastion EC2 (SSM access only)
        │
        ▼
  PARTICIPANT STARTS HERE
        │
        ▼
  Design VPC -> Create EKS -> Create node group -> Create RDS -> Create Redis
  -> Create EFS -> Create S3 -> Configure AppConfig -> Configure IAM for workloads
  -> Deploy Kubernetes -> Configure ALB -> Configure autoscaling -> Configure monitoring
```

Everything below the line is your Day 2 architecture to design - this
starter kit stops at the line on purpose.
