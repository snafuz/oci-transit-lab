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

resource "oci_core_drg" "cloud-drg" {
  provider       = oci.cloud
  compartment_id = var.compartment_ocid
  display_name   = "cloud.drg"
  freeform_tags = {
    "lab" : "network",
    "vpn" : "cloud"
  }
}

resource "oci_core_vcn" "cloud-vcn" {
  provider       = oci.cloud
  cidr_block     = var.cloud-vcn-cidr
  dns_label      = "cloudvcn"
  compartment_id = var.compartment_ocid
  display_name   = "cloud.vcn"
  freeform_tags = {
    "lab" : "network",
    "vpn" : "cloud"
  }
}

resource "oci_core_vcn" "onprem-vcn" {
  provider       = oci.onprem
  cidr_block     = var.onprem-vcn-cidr
  dns_label      = "onpremvcn"
  compartment_id = var.compartment_ocid
  display_name   = "onprem.vcn"
  freeform_tags = {
    "lab" : "network",
    "vpn" : "onprem"
  }
}

resource "oci_core_internet_gateway" "cloud-igw" {
  provider       = oci.cloud
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.cloud-vcn.id
  freeform_tags = {
    "lab" : "network",
    "vpn" : "cloud"
  }
  display_name = "cloud.igw"
}

data "oci_core_services" "cloud-all_services" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

output "all-cloud-services" {
  value = ["${data.oci_core_services.cloud-all_services.services}"]
}

resource "oci_core_service_gateway" "cloud-sg" {
  depends_on = ["null_resource.update-ips"]
  provider       = oci.cloud
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.cloud-vcn.id
  freeform_tags = {
    "lab" : "network",
    "vpn" : "cloud"
  }
  services {
    service_id = "${lookup(data.oci_core_services.cloud-all_services.services[0], "id")}"
  }
  display_name = "cloud.sg"
  route_table_id = "${oci_core_route_table.cloud-sg-rt.id}"
}

resource "oci_core_route_table" "cloud-rt" {
  provider       = oci.cloud
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.cloud-vcn.id
  display_name   = "vpn-rt"
  route_rules {
    destination       = var.onprem-vcn-cidr
    network_entity_id = oci_core_drg.cloud-drg.id
  }
  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.cloud-igw.id
  }
  freeform_tags = {
    "lab" : "network",
    "vpn" : "cloud"
  }
}

resource "oci_core_route_table" "cloud-drg-rt" {
  provider       = oci.cloud
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.cloud-vcn.id
  display_name   = "drg-rt"
  route_rules {
    destination       = "${lookup(data.oci_core_services.cloud-all_services.services[0], "cidr_block")}"
    destination_type  = "SERVICE_CIDR_BLOCK"
    network_entity_id = oci_core_service_gateway.cloud-sg.id
  }
  freeform_tags = {
    "lab" : "network",
    "vpn" : "cloud"
  }
}

resource "oci_core_route_table" "cloud-sg-rt" {
  depends_on = ["null_resource.update-ips"]
  provider       = oci.cloud
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.cloud-vcn.id
  display_name   = "sg-rt"
  route_rules {
    destination       = var.onprem-vcn-cidr
    network_entity_id = oci_core_drg.cloud-drg.id
  }
  freeform_tags = {
    "lab" : "network",
    "vpn" : "cloud"
  }
}


resource "oci_core_security_list" "cloud-sl" {
  provider       = oci.cloud
  display_name   = "cloud-sl"
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.cloud-vcn.id
  freeform_tags = {
    "lab" : "network",
    "vpn" : "cloud"
  }

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }

  ingress_security_rules {
    tcp_options {
      max = 22
      min = 22
    }

    protocol = "6"
    source   = "0.0.0.0/0"
  }
  ingress_security_rules {
    protocol = 1
    source   = var.onprem-vcn-cidr
  }
}

resource "oci_core_drg_attachment" "cloud-drg-att" {
  provider = oci.cloud
  drg_id   = oci_core_drg.cloud-drg.id
  vcn_id   = oci_core_vcn.cloud-vcn.id
  route_table_id = "${oci_core_route_table.cloud-drg-rt.id}"
}

resource "oci_core_subnet" "cloud-sub" {
  provider          = oci.cloud
  cidr_block        = var.cloud-sub-cidr
  display_name      = "cloud.sub"
  dns_label         = "cloudsub"
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_vcn.cloud-vcn.id
  security_list_ids = [oci_core_security_list.cloud-sl.id]
  route_table_id    = oci_core_route_table.cloud-rt.id
  freeform_tags = {
    "lab" : "network",
    "vpn" : "cloud"
  }
}

resource "oci_core_cpe" "cloud-cpe" {
  provider       = oci.cloud
  compartment_id = var.compartment_ocid
  ip_address     = oci_core_instance.libreswan-instance.public_ip
  freeform_tags = {
    "lab" : "network",
    "vpn" : "cloud"
  }
}

resource "oci_core_ipsec" "cloud-ipsec-connection" {
  provider       = oci.cloud
  compartment_id = var.compartment_ocid
  cpe_id         = oci_core_cpe.cloud-cpe.id
  drg_id         = oci_core_drg.cloud-drg.id
  static_routes  = ["0.0.0.0/0"]
  display_name   = "cloud.vpn"
  freeform_tags = {
    "lab" : "network",
    "vpn" : "cloud"
  }
}

resource "oci_core_internet_gateway" "onprem-igw" {
  provider       = oci.onprem
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.onprem-vcn.id
  freeform_tags = {
    "lab" : "network",
    "vpn" : "onprem"
  }
  display_name = "onprem.igw"
}

resource "oci_core_route_table" "onprem-dmz-rt" {
  provider       = oci.onprem
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.onprem-vcn.id
  display_name   = "onprem.dmz-rt"
  freeform_tags = {
    "lab" : "network",
    "vpn" : "onprem"
  }
  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.onprem-igw.id
  }
}

resource "oci_core_route_table" "onprem-secure-rt" {
  provider       = oci.onprem
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.onprem-vcn.id
  display_name   = "onprem.secure-rt"
  freeform_tags = {
    "lab" : "network",
    "vpn" : "onprem"
  }
  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.onprem-igw.id
  }
  route_rules {
    destination       = var.cloud-vcn-cidr
    network_entity_id = data.oci_core_private_ips.libreswan-private-ip-ds.private_ips[0]["id"]
  }
}

resource "oci_core_security_list" "onprem-dmz-sl" {
  provider       = oci.onprem
  display_name   = "onprem-dmz-sl"
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.onprem-vcn.id
  freeform_tags = {
    "lab" : "network",
    "vpn" : "onprem"
  }

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }

  ingress_security_rules {
    tcp_options {
      max = 22
      min = 22
    }

    protocol = "6"
    source   = "0.0.0.0/0"
  }
  ingress_security_rules {
    protocol = 1
    source   = var.cloud-vcn-cidr
  }
  ingress_security_rules {
    protocol = 1
    source   = var.onprem-dmz-sub-cidr
  }
  ingress_security_rules {
    protocol = 50
    source   = "0.0.0.0/0"
  }
}

resource "oci_core_subnet" "onprem-dmz-sub" {
  provider          = oci.onprem
  cidr_block        = var.onprem-dmz-sub-cidr
  display_name      = "onprem.dmz"
  dns_label         = "onpremdmz"
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_vcn.onprem-vcn.id
  security_list_ids = [oci_core_security_list.onprem-dmz-sl.id]
  route_table_id    = oci_core_route_table.onprem-dmz-rt.id
  freeform_tags = {
    "lab" : "network",
    "vpn" : "onprem"
  }
}

resource "oci_core_subnet" "onprem-secure-sub" {
  provider       = oci.onprem
  cidr_block     = var.onprem-secure-sub-cidr
  display_name   = "onprem.secure"
  dns_label      = "onpremsecure"
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.onprem-vcn.id
  route_table_id = oci_core_route_table.onprem-secure-rt.id
  freeform_tags = {
    "lab" : "network",
    "vpn" : "onprem"
  }
}

data "oci_identity_availability_domain" "ad-cloud" {
  provider       = oci.cloud
  compartment_id = var.tenancy_ocid
  ad_number      = 1
}

data "oci_identity_availability_domain" "ad-onprem" {
  provider       = oci.onprem
  compartment_id = var.tenancy_ocid
  ad_number      = 1
}

resource "oci_core_instance" "libreswan-instance" {
  provider            = oci.onprem
  availability_domain = data.oci_identity_availability_domain.ad-onprem.name
  compartment_id      = var.compartment_ocid
  shape               = var.libreswan-shape

  create_vnic_details {
    subnet_id              = oci_core_subnet.onprem-dmz-sub.id
    skip_source_dest_check = "true"
  }
  display_name   = "libreswan"
  hostname_label = "libreswan"
  metadata = {
    ssh_authorized_keys = file(var.ssh_public_key_path)
    user_data           = base64encode(file(var.bootstrapfile))
  }
  source_details {
    source_id   = var.centos7-image[var.regions-map[var.region_onprem]]
    source_type = "image"
  }
  preserve_boot_volume = false
  freeform_tags = {
    "lab" : "network",
    "vpn" : "onprem"
  }
}

resource "oci_core_instance" "cloud-instance" {
  provider            = oci.cloud
  availability_domain = data.oci_identity_availability_domain.ad-cloud.name
  compartment_id      = var.compartment_ocid
  shape               = var.cloud-instance-shape

  create_vnic_details {
    subnet_id = oci_core_subnet.cloud-sub.id
  }
  display_name   = "cloud.instance"
  hostname_label = "cloudinstance"
  metadata = {
    ssh_authorized_keys = file(var.ssh_public_key_path)
  }
  source_details {
    source_id   = var.ol7-image[var.regions-map[var.region_cloud]]
    source_type = "image"
  }
  preserve_boot_volume = false
  freeform_tags = {
    "lab" : "network",
    "vpn" : "cloud"
  }
}

data "oci_core_vnic_attachments" "libreswan-vnic-att-ds" {
  provider       = oci.onprem
  compartment_id = var.compartment_ocid
  instance_id    = oci_core_instance.libreswan-instance.id
}

# Gets the OCID of the first (default) VNIC
data "oci_core_vnic" "libreswan-vnic-ds" {
  provider = oci.onprem
  vnic_id  = data.oci_core_vnic_attachments.libreswan-vnic-att-ds.vnic_attachments[0]["vnic_id"]
}

# List Private IPs
data "oci_core_private_ips" "libreswan-private-ip-ds" {
  provider = oci.onprem
  vnic_id  = data.oci_core_vnic.libreswan-vnic-ds.id
}

resource "null_resource" "update-ips" {
  triggers = {
    libreswan-instance-ids = join(",", oci_core_ipsec.cloud-ipsec-connection.*.id)
  }

  provisioner "local-exec" {
    command = "sleep 9"
  }

  provisioner "remote-exec" {
    connection {
      agent       = false
      timeout     = "10m"
      host        = oci_core_instance.libreswan-instance.public_ip
      user        = "opc"
      private_key = file(var.ssh_private_key_path)
    }

    inline = [
      "sudo service ipsec stop",
      "sudo sed -i 's/__libreswan_instance_private_ip__/${oci_core_instance.libreswan-instance.private_ip}/g' /etc/ipsec.d/oci-ipsec.conf",
      "sudo sed -i 's/__libreswan_instance_public_ip__/${oci_core_instance.libreswan-instance.public_ip}/g' /etc/ipsec.d/oci-ipsec.conf",
      "sudo sed -i 's/__ip_address_tunnel_1__/${data.oci_core_ipsec_config.cloud-ipsec-config.tunnels[0]["ip_address"]}/g' /etc/ipsec.d/oci-ipsec.conf",
      "sudo sed -i 's/__ip_address_tunnel_2__/${data.oci_core_ipsec_config.cloud-ipsec-config.tunnels[1]["ip_address"]}/g' /etc/ipsec.d/oci-ipsec.conf",
      "sudo sed -i 's/__libreswan_instance_public_ip__/${oci_core_instance.libreswan-instance.public_ip}/g' /etc/ipsec.d/oci-ipsec.secrets",
      "sudo sed -i 's/__ip_address_tunnel_1__/${data.oci_core_ipsec_config.cloud-ipsec-config.tunnels[0]["ip_address"]}/g' /etc/ipsec.d/oci-ipsec.secrets",
      "sudo sed -i 's/__ip_address_tunnel_2__/${data.oci_core_ipsec_config.cloud-ipsec-config.tunnels[1]["ip_address"]}/g' /etc/ipsec.d/oci-ipsec.secrets",
      "sudo sed -i 's/__psk1__/${data.oci_core_ipsec_config.cloud-ipsec-config.tunnels[0]["shared_secret"]}/g' /etc/ipsec.d/oci-ipsec.secrets",
      "sudo sed -i 's/__psk2__/${data.oci_core_ipsec_config.cloud-ipsec-config.tunnels[1]["shared_secret"]}/g' /etc/ipsec.d/oci-ipsec.secrets",
      "sudo service ipsec start",
      "sleep 7",
      "sudo ip route add ${var.cloud-vcn-cidr} nexthop dev vti1 nexthop dev vti2",
      "sudo ip route add 129.213.0.128/25 nexthop dev vti1 nexthop dev vti2",
      "sudo ip route add 129.213.2.128/25 nexthop dev vti1 nexthop dev vti2",
      "sudo ip route add 129.213.4.128/25 nexthop dev vti1 nexthop dev vti2",
      "sudo ip route add 130.35.16.0/22 nexthop dev vti1 nexthop dev vti2",
      "sudo ip route add 130.35.96.0/21 nexthop dev vti1 nexthop dev vti2",
      "sudo ip route add 130.35.144.0/22 nexthop dev vti1 nexthop dev vti2",
      "sudo ip route add 130.35.200.0/22 nexthop dev vti1 nexthop dev vti2",
      "sudo ip route add 134.70.24.0/21 nexthop dev vti1 nexthop dev vti2",
      "sudo ip route add 134.70.32.0/22 nexthop dev vti1 nexthop dev vti2",
      "sudo ip route add 138.1.48.0/21 nexthop dev vti1 nexthop dev vti2",
      "sudo ip route add 140.91.10.0/23 nexthop dev vti1 nexthop dev vti2",
      "sudo ip route add 140.91.12.0/22 nexthop dev vti1 nexthop dev vti2",
      "sudo ip route add 147.154.0.0/19 nexthop dev vti1 nexthop dev vti2"
    ]
  }
}

output "libreswan_ips" {
  value = [
    oci_core_instance.libreswan-instance.private_ip,
    oci_core_instance.libreswan-instance.public_ip,
  ]
}

output "cloud-instance_ips" {
  value = [
    oci_core_instance.cloud-instance.private_ip,
    oci_core_instance.cloud-instance.public_ip,
  ]
}

data "oci_core_ipsec_config" "cloud-ipsec-config" {
  ipsec_id = oci_core_ipsec.cloud-ipsec-connection.id
}

output "tunnel-1" {
  value = [
    data.oci_core_ipsec_config.cloud-ipsec-config.tunnels[0]["ip_address"],
    data.oci_core_ipsec_config.cloud-ipsec-config.tunnels[0]["shared_secret"],
  ]
}

output "tunnel-2" {
  value = [
    data.oci_core_ipsec_config.cloud-ipsec-config.tunnels[1]["ip_address"],
    data.oci_core_ipsec_config.cloud-ipsec-config.tunnels[1]["shared_secret"],
  ]
}

