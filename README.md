# morays-docker-terraform


# Morays Website — Amazon ECS Fargate with Terraform

**Part 2 of the project: infrastructure as code and automated deployment.**

This is an AWS learning/demo deployment for the existing `morays-app` Apache website. Terraform creates the cloud resources; `deploy.sh` handles Docker image build, ECR push, and deployment. It does **not** modify your Windows or Ubuntu Docker installation.

## Architecture

```text
Your Ubuntu VS Code terminal
  └── ./deploy.sh
        ├── Terraform (01-ecr) → Amazon ECR repository [optional]
        ├── Docker build → Docker login to ECR → Docker push
        └── Terraform (02-ecs)
              ├── VPC (10.40.0.0/16)
              ├── Internet gateway + route table
              ├── 2 PUBLIC subnets in separate Availability Zones
              ├── Public Application Load Balancer (port 80)
              │     └── Target group (IP targets, health check GET /)
              ├── ECS Cluster / ECS Service (1 Fargate task)
              │     ├── Apache container (port 80)
              │     ├── IAM execution role (ECR pull / CloudWatch logs)
              │     └── Security group: port 80 only from ALB security group
              └── CloudWatch Logs (7-day retention)

Internet → ALB → ECS Fargate task → Apache → index.html
```

**No EC2 instances, no database, no NAT gateway.** This example uses Fargate tasks in public subnets with a public IP for outbound ECR access, but only the ALB can connect to their application port. The deployment creates **one task**, not two, even though two Availability Zones are configured; increasing `desired_count` to `2` can improve availability at additional cost.

This example exposes **HTTP, not HTTPS**. Production improvements: ACM + HTTPS listener, Route 53 DNS, private task subnets + NAT or appropriate VPC endpoints, scaling, alarms, remote Terraform state and secure CI/CD.

## Folder map

```text
morays-ecs-terraform/
├── 01-ecr/
│   ├── versions.tf           AWS provider, region
│   ├── main.tf               ECR repository, retention policy
│   └── outputs.tf            Repository URI
├── 02-ecs/
│   ├── versions.tf           Provider settings
│   ├── variables.tf          Image URI, region, counts and CIDRs
│   ├── network.tf            VPC, subnets, IGW, routes
│   ├── security.tf           Two security groups
│   ├── iam.tf                ECS task execution permissions
│   ├── alb.tf                ALB, target group, listener
│   ├── ecs.tf                ECS cluster, Fargate task/service and logs
│   ├── outputs.tf            ALB website URL, names and image URI
│   └── terraform.tfvars.example
├── sample-site/              OPTIONAL test site; use your own Morays site by default
│   ├── Dockerfile
│   └── index.html
├── deploy.sh                 Automated build, push and Terraform deployment
├── verify.sh                 Check website and ECS task count
├── destroy.sh                Remove infrastructure when finished
└── .gitignore                Keep state and local secrets out of Git
```

## Prerequisites

1. Windows Docker Desktop running. Earlier, `docker.exe` worked from your Ubuntu WSL terminal while the Linux `docker` command failed. The scripts **prefer `docker.exe`** when it is available.
2. AWS CLI installed/configured **inside Ubuntu WSL**, with permissions to create ECR, ECS, ALB, VPC, IAM and CloudWatch resources. For an AWS organisation using IAM Identity Center, use `aws configure sso`; otherwise configure a credential method permitted by your organisation. Do not commit access keys in Terraform or Git.
3. Terraform CLI >= 1.5 installed **inside Ubuntu WSL**.
4. Your Morays website is in `~/morays-project/morays-docker` with `Dockerfile` and `index.html` (as used in the Docker build earlier).
5. A working AWS billing account. **AWS charges apply even if you never open the site.**

Check the tools:

```bash
terraform -version
aws --version
aws sts get-caller-identity
# This was proven working in your environment:
docker.exe run --rm hello-world
```

**Default AWS Region: London (`eu-west-2`).** Use another region by prefixing `AWS_REGION=your-region`. Keep ECR and ECS in the same region for this lab. The AWS account ID and repository URL are read automatically; do **not** copy the example `123456789012` into real commands.

## Fast path A — You have the Morays image locally, but NOT in ECR

From the extracted project folder, in your **Ubuntu** VS Code terminal:

```bash
cd ~/morays-ecs-terraform
chmod +x deploy.sh verify.sh destroy.sh
./deploy.sh
```

Type `DEPLOY` when prompted to authorise resources that may incur charges.

The script runs these actions automatically:

1. Checks AWS credentials and Docker connectivity.
2. Uses Terraform to create an ECR repository named `morays-ecs-website`.
3. Builds your `~/morays-project/morays-docker` Dockerfile as a Linux AMD64 image (your Apache site).
4. Gives it a unique version tag, signs Docker into ECR and pushes the image.
5. Uses Terraform to provision VPC, two public subnets, IAM, security groups, ALB, CloudWatch, ECS cluster, task definition and ECS service.
6. Prints the load balancer's HTTP website URL.

Verify:

```bash
./verify.sh
```

This reports the ECS service's Desired and Running task counts and requests the ALB URL. If DNS has just been created, browser access may take some time to become available.

### If your website folder is different

Supply the absolute path to your folder containing `Dockerfile`:

```bash
SOURCE_DIR="$HOME/morays-project/morays-docker" ./deploy.sh
```

Or test with the included simple HTML example:

```bash
SOURCE_DIR="$PWD/sample-site" ./deploy.sh
```

**Don't deploy both independently unless you intend to update the website:** running `deploy.sh` again uses the same Terraform infrastructure state and creates a new task revision.

## Fast path B — Your image ALREADY exists in ECR from Part 1

Skip building/pushing and don't create a duplicate ECR repository:

```bash
EXISTING_IMAGE_URI='YOUR_ACCOUNT_ID.dkr.ecr.eu-west-2.amazonaws.com/httpd-website:latest' ./deploy.sh
```

Replace that full URI with **the exact existing ECR image URI** from the AWS console. The script still provisions a **new Terraform-managed network, ALB and ECS service**. It does not adopt your existing manually created resources automatically. If you want Terraform to manage previously-created console resources *in place*, you would need a separate `terraform import`/configuration reconciliation project.

## Fast path C — Your ECR repository exists, but you want to push the LOCAL Morays image

```bash
ECR_REPOSITORY_URI='YOUR_ACCOUNT_ID.dkr.ecr.eu-west-2.amazonaws.com/httpd-website' ./deploy.sh
```

This reuses the repository and pushes a new uniquely-tagged image into it. You need ECR push permissions. Your ECR repository itself will not be added to Terraform state by this option.

## Manual Terraform steps, for learning

If you want to understand the stages instead of running `deploy.sh`:

### 1. Provision the ECR repository

```bash
cd 01-ecr
terraform init
terraform plan -var='aws_region=eu-west-2'
terraform apply -var='aws_region=eu-west-2'
terraform output -raw repository_url
```

### 2. Docker build/login/push

The project script performs these steps with the correct account, repository URI and unique image tag. The following is only a generic example; replace `ECR_URI` with the URI from the previous command:

```bash
ECR_URI="$(terraform output -raw repository_url)"
AWS_REGION=eu-west-2
cd ~/morays-project/morays-docker
docker.exe build --platform linux/amd64 -t morays-app:1.0 .
docker.exe tag morays-app:1.0 "$ECR_URI:1.0"
aws ecr get-login-password --region "$AWS_REGION" | docker.exe login --username AWS --password-stdin "${ECR_URI%%/*}"
docker.exe push "$ECR_URI:1.0"
```

**Important:** The ECR repo created by this sample is tag-immutable; `:1.0` can be pushed only once. Later deployments must use new tags, which `deploy.sh` does automatically.

### 3. Create ECS and the load balancer with Terraform

```bash
cd ~/morays-ecs-terraform/02-ecs
terraform init
terraform plan -var='aws_region=eu-west-2' -var='image_uri=YOUR_FULL_ECR_IMAGE_URI'
terraform apply -var='aws_region=eu-west-2' -var='image_uri=YOUR_FULL_ECR_IMAGE_URI'
terraform output website_url
```

## What each Terraform resource does

| File | AWS resource | Simple explanation |
|---|---|---|
| `01-ecr/main.tf` | ECR repository | Private storage for your Apache Docker image. |
| `network.tf` | `aws_vpc` | Your own AWS virtual network. |
| `network.tf` | `aws_subnet` | Two public networks in different AZs. |
| `network.tf` | Internet gateway and route table | Allow the load balancer and public-IP tasks to reach the internet. |
| `security.tf` | ALB security group | Let visitors connect to port 80. |
| `security.tf` | Task security group | Allow requests to Apache **only from the ALB**. |
| `iam.tf` | IAM execution role | Let ECS pull the image and send CloudWatch logs. |
| `alb.tf` | ALB | Receive internet traffic and forward it to healthy containers. |
| `alb.tf` | IP target group | Keep track of which Fargate task IP to route traffic to. |
| `alb.tf` | Listener | Accept HTTP requests on port 80. |
| `ecs.tf` | ECS Cluster | Logical home for the Fargate service. |
| `ecs.tf` | Task Definition | Recipe: image, CPU, memory, port, logging and execution role. |
| `ecs.tf` | ECS Service | Keep one task running and register it with the ALB. |
| `ecs.tf` | CloudWatch Log Group | Store Apache container stdout/stderr, retained for 7 days. |
| `outputs.tf` | Website URL | Prints the ALB DNS address after deployment. |

## Updates and versioning

Edit `index.html` and run `./deploy.sh` again. It generates a new immutable image tag, pushes it, updates the task definition and instructs ECS to deploy the new revision. The same VPC, ALB and cluster stay managed by Terraform. Temporary extra tasks can run while an update is rolling out.

## Verify in the AWS Console

- **Amazon ECR → Private repositories → morays-ecs-website**: the pushed image and tag (unless you reused an existing repo).
- **Amazon ECS → Clusters → morays-ecs-demo-cluster → Services**: a service with desired count 1, ideally running count 1.
- **EC2 → Load balancers → morays-ecs-demo-alb**: check that the ALB is active and copy its DNS name.
- **EC2 → Target groups → morays-ecs-demo-tg → Targets**: check that your Fargate task target is healthy.
- **CloudWatch → Log groups → /ecs/morays-ecs-demo**: Apache logs and startup errors.

## Troubleshooting

| Symptom | What to check |
|---|---|
| `docker` says `/var/run/docker.sock` missing | Use `docker.exe`, as verified on your WSL system. |
| `terraform: command not found` | Install Terraform in Ubuntu; verify with `terraform -version`. |
| `aws: command not found` or `Unable to locate credentials` | Install/configure AWS CLI inside Ubuntu and run `aws sts get-caller-identity`. |
| `AccessDenied` from AWS | Your AWS identity lacks one of the IAM/VPC/ECS/ALB/ECR permissions. Read the error; don't add wildcard admin policies just to bypass it. |
| `CannotPullContainerError` | Check the ECR image URI, execution role, image location/region, subnet internet route and task public IP. |
| ECS task stops | Open ECS service Events and CloudWatch logs. |
| Unhealthy target | Ensure `index.html` is served by Apache at `/` on port 80. ALB health check is HTTP GET `/`. |
| ECR push says image tag is immutable | Choose a different tag, or use the deploy script, which creates a fresh tag. |
| `NoCredentialProviders` or token expired | Reauthenticate via your AWS credential method (e.g. `aws sso login`). |
| Terraform reports resources already exist | It does not automatically manage things created manually in Part 1. Use different names or import deliberately. |
| Terraform destroy says state missing | Do not blindly delete resources; locate/recover the state and reconcile the account. |

## Costs and cleanup — IMPORTANT

This is **not free just because it is a static site**. Possible costs: Application Load Balancer hours and capacity units, Fargate vCPU/memory time, public IPv4 addresses, ECR storage/scanning, CloudWatch, data transfer and other regional charges. Even one running task and ALB can generate ongoing charges. Confirm current prices at the AWS Pricing pages for your selected Region before applying.

**Always clean up when finished testing.** To remove the Terraform-managed ECS cluster, Fargate service, ALB, VPC, IAM role and CloudWatch group:

```bash
./destroy.sh
```

Type `DESTROY` when prompted. This **keeps ECR by default**.

To also permanently delete the **dedicated** ECR repository created by `01-ecr`, including its stored images:

```bash
DELETE_ECR=1 ./destroy.sh
```

It will ask for another explicit confirmation. **Never use this cleanup to delete someone else's or a shared ECR repository.** `01-ecr/main.tf` sets `force_delete = true` for a lab repository; in production you would turn that off.

**Keep the `.tfstate` files.** These local files are Terraform's record of what it created, and `destroy.sh` relies on them. Back them up securely; do not add them to Git. A production team should use a remote state backend with locking and encryption, GitHub Actions with short-lived OIDC credentials, HTTPS/ACM and private subnets.

## References

- ECS Fargate task networking: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/fargate-task-networking.html
- ECR push and authentication: https://docs.aws.amazon.com/AmazonECR/latest/userguide/docker-push-ecr-image.html
- ECS task execution roles: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_execution_IAM_role.html
- Terraform AWS ECS service documentation: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service



commands to run:

cd ~/morays-project/morays-docker-terraform

ls -la

chmod +x deploy.sh verify.sh destroy.sh

aws sts get-caller-identity

./deploy.sh

./verify.sh

./destroy.sh