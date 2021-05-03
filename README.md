# balenaOS SOCKS proxy tunnel
> [redirect](https://www.balena.io/docs/reference/OS/network/2.x/#connecting-behind-a-proxy) all TCP traffic (except VPN) from balenaOS devices via a SOCKS5 proxy SSH tunnel running on DigitalOcean or AWS/EC2


## ToC
* [overview](#overview)
* [generate keys](#generate-keys)
* [cloud proxy server](#cloud-proxy-server)
* [balenaCloud application](#balenacloud-application)
* [test and verify](#test-and-verify)
* [troubleshooting](#troubleshooting)


## overview
The examples give below demonstrate how to forward/redirect all balenaOS traffic via a 
user provided proxy. In the specific instance, we use a SOCKS5 proxy, which we tunnel to 
over SSH on DigitalOcean and AWS/EC2 using public key authentication.

Configuration of the hostOS is done within a ~ 10MB container on the host network. This 
container interacts with the [Supervisor API](https://www.balena.io/docs/reference/supervisor/supervisor-api/) 
to configure the redsocks redirector. As well as configuring the redirector, the 
container optionally establishes a tunnel to a remote server via SSH, if a private key is 
provided.

The redirection on the host is performed by [redsocks](https://github.com/darkk/redsocks) 
using iptables. Redsocks supports `socks4`, `socks5`, `http-connect`, and `http-relay` proxy 
types, and while in these examples we use `socks5` (default), any supported proxy type 
can be deployed and used.

In our example, we do not enable proxy authentication, since we are already tunneling to 
it via SSH, however in case where such local tunneling may not be desirable, setting 
`PROXY_LOGIN` and `PROXY_PASSWORD` environment variables and omitting `SSH_PRIVATE_KEY` 
will not create a tunnel and assume direct communication with the proxy using provided 
proxy authentication credentials.

The general approach uses in this example is as follows:

* decide which cloud provider to use for hosting the proxy server (i.e. Digital Ocean or AWS)
* generate test SSH keys, using an appropriate format for the selected cloud provider
* deploy a proxy server using Terraform into the selected cloud provider
* create a balenaCloud application
* build and deploy a release
* provision a balenaOS device (e.g balenaFin, RaspberryPi, Intel NUC, etc.)
* test and verify
* destroy test resources to avoid unexpected billing


## generate keys
> generate SSH keys for proxy tunnel authentication

    mkdir -p keys


### EC
> EC keys can be used with DigitalOcean servers

    ssh_key_type=ed25519

    ssh-keygen -o -a 100 -t "${ssh_key_type}" -f "keys/id_${ssh_key_type}" -C 'balena' -N ''

    ssh_public_key="$(cat keys/id_ed25519.pub)"

    ssh_private_key="$(cat keys/id_ed25519 | openssl base64 -A)"


### RSA
> used for AWS/EC2 since EC cryptography is not supported at the time of writing

    ssh_key_type=rsa

    ssh-keygen -t "${ssh_key_type}" -f "keys/id_${ssh_key_type}" -C 'balena' -N ''

    ssh_public_key="$(cat keys/id_rsa.pub)"

    ssh_private_key="$(cat keys/id_rsa | openssl base64 -A)"


## cloud proxy server
> deploy a proxy server into a desired cloud provider

### DigitalOcean
> deploy a [DigitalOcean](https://cloud.digitalocean.com/account/api/tokens) cloud proxy server using [Terraform](https://www.terraform.io/downloads.html)

### create proxy server

    export DO_TOKEN={{ digital-ocean-api-token }}
    
    pushd terraform/digitalocean
    
    terraform init

    terraform plan -var "do_token=${DO_TOKEN}"  
  
    terraform apply -var "do_token=${DO_TOKEN}"
    
    proxy_ip="$(terraform output -json | jq -r .ipv4_address.value)"

    ssh_user=root

    popd

#### (finally) clean up resources
> optionally destroy DigitalOcean Droplet after finishing with the PoC

    pushd terraform/digitalocean

    terraform destroy -var "do_token=${DO_TOKEN}"

    popd


### AWS/EC2
> deploy a cloud proxy server into AWS/EC2 using Terraform

#### create proxy server
> ensure your AWS credentials are configured correctly

    pushd terraform/aws-ec2

    terraform init

    terraform plan -var "key_pair=${ssh_public_key}"

    terraform apply -var "key_pair=${ssh_public_key}"

    proxy_ip="$(terraform output -json | jq -r .instance_public_ip.value)"
    
    ssh_user=ec2-user

    popd


#### (finally) clean up resources
> optionally destroy AWS/EC2 resources after finishing with the PoC

    pushd terraform/aws-ec2

    terraform destroy -var "key_pair=${ssh_public_key}"

    popd


## balenaCloud application
> deploy balenaCloud application, which will configure balenaOS to proxy all traffic via your cloud proxy

### build and deploy the app
> once the app is created and the release is deployed, [provision](https://www.balena.io/docs/learn/getting-started/raspberrypi3/nodejs/#add-your-first-device) at least one balenaOS device into it

    pushd app

    balena login

    arch=armv7l

    device_type=fincm3

    app_name=${device_type}-${arch}

    balena app create ${app_name} --type ${device_type}

    app_slug=$(balena app ${app_name} | grep SLUG | awk '{print $2}')

    balena env add SSH_USER "${ssh_user}" --application ${app_slug}

    balena env add SSH_KEY_TYPE "${ssh_key_type}" --application ${app_slug}

    balena env add SSH_PRIVATE_KEY "${ssh_private_key}" --application ${app_slug}

    balena env add PROXY_IP "${proxy_ip}" --application ${app_slug}

    balena push ${app_slug}
    
    popd


## test and verify
> terminal into the hostOS container and verify all traffic is exiting via your proxy

### DigitalOcean

    echo 'curl -s https://ipinfo.io/org; exit' \
      | balena ssh $(balena devices --app ${app_name} -j | jq -r .[0].uuid)

	=============================================================
		Welcome to balenaOS
	=============================================================
	AS14061 DigitalOcean, LLC


### AWS/EC2

    ...
    
	=============================================================
		Welcome to balenaOS
	=============================================================
	AS16509 Amazon.com, Inc.


## troubleshooting

* test proxy connectivity bypassing redsocks redirector on the balenaOS device

```
curl -x socks5://127.0.0.1:1080 https://ipinfo.io/
```

* to temporarily restore access in the event of proxy connectivity issues, on the hostOS run the following

```
iptables -t nat -F OUTPUT
iptables -t nat -F PREROUTING
iptables -t nat -F REDSOCKS
```
