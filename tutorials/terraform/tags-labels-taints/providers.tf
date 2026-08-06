terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=4.81.0"
    }
    # azapi is needed only for the Managed Gateway API installation, which azurerm
    # does not expose yet (hashicorp/terraform-provider-azurerm#31710).
    azapi = {
      source  = "azure/azapi"
      version = "=2.10.0"
    }
  }
}

# Dual-target configuration: every identity field defaults to null (Azure CLI auth
# against real Azure). deploy.sh passes the LocalStack values when targeting the
# emulator: metadata_host=localhost.localstack.cloud:4566, all-zero GUIDs for
# subscription/tenant/client, and the placeholder client secret.
provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    key_vault {
      # Auto-purge on real Azure (prevents the soft-delete global-name lock on
      # re-runs); skipped on the emulator, which keeps no soft-deleted vaults and
      # 404s the purge call (DeletedVaultNotFound), failing the destroy.
      purge_soft_delete_on_destroy = var.metadata_host == null
    }
  }

  metadata_host   = var.metadata_host
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
  client_id       = var.client_id
  client_secret   = var.client_secret

  # The emulator has no resource-provider registration surface.
  resource_provider_registrations = var.metadata_host == null ? null : "none"
}

# azapi does not use azurerm's metadata_host discovery: when targeting the emulator
# deploy.sh passes resource_manager_endpoint explicitly and instance discovery is
# disabled (the emulator authority is not known to the Entra metadata service, the
# same reason `lstk az start-interception` sets core.instance_discovery=false for
# the az CLI).
provider "azapi" {
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
  client_id       = var.client_id
  client_secret   = var.client_secret

  disable_instance_discovery = var.resource_manager_endpoint == null ? null : true

  endpoint = var.resource_manager_endpoint == null ? null : [{
    resource_manager_endpoint       = var.resource_manager_endpoint
    active_directory_authority_host = var.resource_manager_endpoint
    resource_manager_audience       = var.resource_manager_endpoint
  }]
}
