provider "oci" {
  alias            = "cloud"
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = var.regions-map[var.region_cloud]
}
provider "oci" {
  alias            = "onprem"
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = var.regions-map[var.region_onprem]
}