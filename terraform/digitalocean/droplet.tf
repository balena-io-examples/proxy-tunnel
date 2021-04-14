resource "digitalocean_ssh_key" "balena" {
  name = "balena"
  public_key = file("../../keys/id_ed25519.pub")
}

resource "digitalocean_droplet" "openssh-server" {
    image = "ubuntu-20-04-x64"
    name = "openssh-server"
    region = "nyc3"
    size = "s-1vcpu-1gb"
    ssh_keys = [digitalocean_ssh_key.balena.fingerprint]
}

output "ipv4_address" {
  value = digitalocean_droplet.openssh-server.ipv4_address
}
