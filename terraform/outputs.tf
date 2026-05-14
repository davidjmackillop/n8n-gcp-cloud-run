output "n8n_url" {
  description = "URL of the deployed n8n instance."
  value       = google_cloud_run_v2_service.n8n.uri
}

output "cloud_run_service_account" {
  description = "Service account used by the Cloud Run n8n service."
  value       = google_service_account.cloud_run.email
}
