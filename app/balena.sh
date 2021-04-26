#!/bin/sh

set -eu

# https://www.balena.io/docs/reference/OS/network/2.x/#connecting-behind-a-proxy
proxy_ipv4=${PROXY_IP:-}
proxy_user=${PROXY_LOGIN:-}
proxy_pass=${PROXY_PASSWORD:-}
proxy_port=${PROXY_PORT:-1080}
proxy_type=${PROXY_TYPE:-socks5}
ssh_user=${SSH_USER:-root}
ssh_port=${SSH_PORT:-22}
ssh_private_key=${SSH_PRIVATE_KEY:-}
ssh_key_type=${SSH_KEY_TYPE:-}


# if provided, decode and store SSH key material
if [ "${ssh_private_key}" != '' ] && [ "${ssh_key_type}" != '' ]; then
    mkdir -p "${HOME}/.ssh"
    ssh_private_key_file="${HOME}/.ssh/id_${ssh_key_type}"
    touch "${ssh_private_key_file}"
    chmod 0600 "${ssh_private_key_file}"
    echo "${ssh_private_key}" | base64 -d > "${ssh_private_key_file}"
fi

# https://www.balena.io/docs/reference/supervisor/supervisor-api/#patch-v1devicehost-config
if [ "${proxy_ipv4}" != '' ]; then
    tmpconfig="$(mktemp)"
    config="$(mktemp)"
    echo "{\"network\":{\"proxy\":{\"noProxy\":[\"${proxy_ipv4}\"],\"type\":\"${proxy_type}\",\"ip\":\"${proxy_ipv4}\",\"port\":${proxy_port}}}}" | jq -r > "${config}"
    cat < "${config}" > "${tmpconfig}"
    
    # handle proxy authentication
    if [ "${proxy_user}" != '' ] && [ "${proxy_pass}" != '' ]; then
        cat < "${config}" | jq ".network.proxy += {\"login\":\"$proxy_user\"}" > "${tmpconfig}"
        cat < "${tmpconfig}" > "${config}"
        cat < "${config}" | jq ".network.proxy += {\"password\":\"$proxy_pass\"}" > "${tmpconfig}"
        cat < "${tmpconfig}" > "${config}"
    fi
    
    # handle SSH tunnel
    [ -f "${ssh_private_key_file}" ] &&  cat < "${config}" \
      | jq ".network.proxy += {\"ip\":\"127.0.0.1\"}" > "${tmpconfig}"
    cat < "${tmpconfig}" > "${config}"

	# enable redsocks redirector
    cat < "${config}" | jq && curl -X PATCH "${BALENA_SUPERVISOR_ADDRESS}/v1/device/host-config?apikey=${BALENA_SUPERVISOR_API_KEY}" \
      --header 'Content-Type:application/json' \
      --data "$(cat "${config}")"
else
	# disable redsocks redirector
    curl -X PATCH "${BALENA_SUPERVISOR_ADDRESS}/v1/device/host-config?apikey=${BALENA_SUPERVISOR_API_KEY}" \
      --header 'Content-Type:application/json' \
      --data '{}'
fi

# open SSH tunnel to a SOCKS proxy if all the conditions are met
if [ "${proxy_ipv4}" != '' ] && [ -f "${ssh_private_key_file}" ]; then
  exec ssh -vCND "127.0.0.1:${proxy_port}" \
    -o StrictHostKeyChecking=no \
    -i "${ssh_private_key_file}" \
    -p "${ssh_port}" \
    "${ssh_user}@${proxy_ipv4}" "@$"
fi
