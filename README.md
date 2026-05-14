# n8n on GCP Cloud Run

Deploy n8n to Google Cloud Run using Terraform and GitHub Actions.

- One-click deploy from GitHub Actions
- Cloud SQL PostgreSQL for durable storage
- Secret Manager for database credentials and the n8n encryption key
- Optional scale-to-zero for low-cost testing

## What Gets Created

- Cloud Run service running `n8nio/n8n:latest`
- Cloud SQL PostgreSQL instance and database
- Secret Manager secrets for credentials
- Dedicated Cloud Run runtime service account
- GCS bucket for Terraform state (created by the deploy workflow)

## Quickstart

### 1. Create a GCP Project

Create or choose a Google Cloud project with billing enabled.

### 2. Create a Service Account Key

1. Open Google Cloud Console.
2. Go to **IAM & Admin > Service Accounts**.
3. Create a service account, for example `github-n8n-deployer`.
4. Grant it the **Owner** role for the first deploy. You can scope this down later.
5. Create a JSON key for the service account.

### 3. Store the Key in GitHub Secrets

1. In your GitHub repo, go to **Settings > Secrets and variables > Actions**.
2. Create a repository secret named `GCP_SA_KEY`.
3. Paste the full JSON key as the value.

### 4. Deploy

1. Go to **Actions > Deploy n8n to GCP Cloud Run > Run workflow**.
2. Enter your `project_id`.
3. The workflow bootstraps a Terraform state bucket, validates the config, and applies it.

When finished, the workflow prints the `n8n_url`. Open it in your browser.

## Scaling

| Goal | min_instances | max_instances |
| --- | ---: | ---: |
| Lowest cost | `0` | `1` |
| Reliable schedules | `1` | `1` |
| Small production | `1` | `3` |

Use `min_instances = 1` if you run scheduled workflows or need webhooks to be responsive.

## Custom Domain

This repo deploys n8n on the default Cloud Run URL. If you want a custom domain:

1. Map your domain to the Cloud Run service in the Cloud Console or with `gcloud`.
2. Update the `N8N_HOST` and `WEBHOOK_URL` environment variables in `terraform/main.tf`.

## Destroy

Go to **Actions > Destroy n8n on GCP Cloud Run > Run workflow**. Enter the same `project_id`, `region`, and `service_name` used during deployment.

The Terraform state bucket is intentionally left in place so you can redeploy later.

## Repository Structure

```
.
├── .github/workflows/
│   ├── deploy.yml
│   ├── destroy.yml
│   └── validate.yml
├── terraform/
│   ├── main.tf
│   ├── outputs.tf
│   ├── variables.tf
│   └── terraform.tfvars.example
├── LICENSE
└── README.md
```

## Customizing

Edit `terraform/variables.tf` to change defaults (region, timezone, database tier, etc.). For one-off overrides, create a `terraform/terraform.tfvars` file or pass `-var` flags.

## License

MIT
