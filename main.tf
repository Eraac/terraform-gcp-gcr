locals {
  resource_level = "PROJECT"
  project_id     = data.google_project.selected.project_id
  service_account_name = var.use_existing_service_account ? (
    var.service_account_name
    ) : (
    length(var.service_account_name) > 0 ? var.service_account_name : "${var.prefix}-lw-${random_id.uniq.hex}"
  )
  service_account_json_key = jsondecode(var.use_existing_service_account ? (
    base64decode(var.service_account_private_key)
    ) : (
    base64decode(module.lacework_gcr_svc_account.private_key)
  ))
  gcr_apis = var.required_gcr_apis
}

resource "random_id" "uniq" {
  byte_length = 4
}

data "google_project" "selected" {
  project_id = var.project_id
}

module "lacework_gcr_svc_account" {
  source               = "lacework/service-account/gcp"
  version              = "~> 1.0"
  create               = var.use_existing_service_account ? false : true
  service_account_name = local.service_account_name
  project_id           = local.project_id
}

resource "google_project_service" "required_apis_for_gcr_integration" {
  for_each = local.gcr_apis
  project  = local.project_id
  service  = each.value

  disable_on_destroy = false
}

// Role(s) for a GCR integration
resource "google_project_iam_member" "for_gcr_integration" {
  project = local.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${local.service_account_json_key.client_email}"
}

# wait for X seconds for things to settle down in the GCP side
# before trying to create the Lacework external integration
resource "time_sleep" "wait_time" {
  create_duration = var.wait_time
  depends_on = [
    module.lacework_gcr_svc_account,
    google_project_service.required_apis_for_gcr_integration,
    google_project_iam_member.for_gcr_integration
  ]
}

resource "lacework_integration_gcr" "default" {
  name            = var.lacework_integration_name
  registry_domain = var.registry_domain
  credentials {
    client_id      = local.service_account_json_key.client_id
    private_key_id = local.service_account_json_key.private_key_id
    client_email   = local.service_account_json_key.client_email
    private_key    = local.service_account_json_key.private_key
  }
  limit_by_tags          = var.limit_by_tags  
  limit_by_labels        = var.limit_by_labels   
  limit_by_repositories  = var.limit_by_repositories
  limit_num_imgs         = var.limit_num_imgs
  non_os_package_support = var.non_os_package_support
  depends_on             = [time_sleep.wait_time]
}
