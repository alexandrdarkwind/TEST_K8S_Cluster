terraform {
  required_version = ">= 0.13"
  required_providers {
    hcloud = {
      source = "hetznercloud/hcloud"
    }
  }
}

provider "hcloud" {
  token = var.hcloud_token
}

resource "hcloud_ssh_key" "admin_k8s" {
  name       	= "admin_k8s"
  public_key 	= file(var.ssh_public_key)
}

resource "hcloud_server" "k8s" {
  for_each 	= var.servers
  name		= each.key
  server_type	= each.value
  location    	= var.location
  image       	= var.server_image
  ssh_keys 	= [
  hcloud_ssh_key.admin_k8s.id]

 connection {
    host        = self.ipv4_address
    type        = "ssh"
    private_key = file(var.ssh_private_key)
 }

 provisioner "file" {
    source      = "scripts/ssh-port.sh"
    destination = "/root/ssh-port.sh"
 }

 provisioner "remote-exec" {
       inline 	= [
         "SSH_PORT=${var.ssh_port} bash /root/ssh-port.sh"
        ]
 }

}

variable "hcloud_token" {
#  default = ""
}
### export HCLOUD_TOKEN=

variable "location" {
  default = "hel1"
}

variable "servers" {
  type = map(string)
  default = {
	"node1" : "cx21"
	"node2" : "cx21"
	"node3" : "cx21"
	"node4" : "cx21"
  }
}

variable "server_image" {
  description = "Predefined Image that will be used to spin up the machines (Currently supported: ubuntu-20.04, ubuntu-18.04)"
  default     = "ubuntu-20.04"
}

variable "ssh_private_key" {
  description = "Private Key to access the machines"
  default = "./ssh_key/id_rsa"
}

variable "ssh_public_key" {
  description = "Public Key to authorized the access for the machines"
  default = "./ssh_key/id_rsa.pub"
}

variable "ssh_port" {
  default = "22"
}


resource "null_resource" "setup" {
  depends_on = [
    hcloud_server.k8s
  ]

  for_each      = var.servers

  connection {
    host        = hcloud_server.webinar[each.key].ipv4_address
    type        = "ssh"
    port        = var.ssh_port
    private_key = file(var.ssh_private_key)
  }

 provisioner "remote-exec" {
       inline = [
         "apt-get update && apt-get install -y linux-headers-$(uname -r)"
       ]
 }

}

output "servers_id" {
  value = tomap({for k, inst in hcloud_server.k8s : k=> inst.id})
}

output "server_ips" {
  value = tomap({for k, inst in hcloud_server.k8s : k=> inst.ipv4_address})
}

output "server_name" {
  value = values(hcloud_server.k8s)[*].name
}


