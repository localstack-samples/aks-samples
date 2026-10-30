# The defaults of the cluster scripts. deploy.sh overrides each of them from its environment variables.
prefix            = "local"
suffix            = "test"
location          = "italynorth"
identity_type     = "SystemAssigned"
network_option    = 1
system_node_count = 1
user_node_count   = 1
node_vm_size      = "Standard_D4ds_v5"
os_sku            = "AzureLinux"
os_disk_size_gb   = 50
os_disk_type      = "Ephemeral"
max_pods          = 100
