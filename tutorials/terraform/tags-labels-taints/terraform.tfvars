prefix = "local"
suffix = "test"

tags = {
  env = "test"
  iac = "terraform"
}

system_node_pool_node_labels = {
  team = "platform"
}

user_node_pool_name = "upool1"

user_node_pool_node_labels = {
  workload = "batch"
}

user_node_pool_node_taints = [
  "dedicated=batch:NoSchedule"
]

user_node_pool_tags = {
  costcenter = "1234"
}

# Explicit, globally unique vault name for real Azure (derived defaults collided
# twice with names already reserved elsewhere — Key Vault names are global across
# Azure). deploy.sh overrides this with local-kv-test on the emulator.
key_vault_name = "local-kv-ciao-local"

gateway_api_enabled                     = true
oidc_issuer_enabled                     = true
workload_identity_enabled               = true
azure_keyvault_secrets_provider_enabled = true
vertical_pod_autoscaler_enabled         = true
blob_csi_driver_enabled                 = true
disk_csi_driver_enabled                 = true
file_csi_driver_enabled                 = true
rbac_enabled                            = true
aad_enabled                             = true
aad_azure_rbac_enabled                  = true
aad_admin_group_object_ids              = []
system_node_pool_node_count             = 1
system_node_pool_min_count              = 1
system_node_pool_max_count              = 3
user_node_pool_node_count               = 1
user_node_pool_min_count                = 1
user_node_pool_max_count                = 3

