#!/bin/sh -e

required_commands="openssl curl htpasswd jq base64"

for command in $required_commands; do
	if ! command -v $command > /dev/null; then
		echo "Missing required executable: $command" >&2
		exit 1
	fi
done

ask_yes_no() {
	while true; do
		read -p "$1 [y/n] " yn
		case $yn in
			[Yy]* ) return 0;;
			[Nn]* ) return 1;;
			* ) echo "Please answer yes or no.";;
		esac
	done
}

should_generate_registry_secrets() {
	if [ -f $HDCI_FOLDER/registry-auth/.htpasswd ] || [ -f $HDCI_FOLDER/registry-auth/watchtower/config.json ]; then
		ask_yes_no "Registry secrets already exist. (maybe partially) Do you want to generate them again?"
		return $?
	fi
	return 0
}

generate_registry_secrets() {
	rm -rf $HDCI_FOLDER/registry-auth
	mkdir -p $HDCI_FOLDER/registry-auth/watchtower
	user=$(generate_secret)
	pass=$(generate_secret)
	htpasswd -Bbc $HDCI_FOLDER/registry-auth/.htpasswd $user $pass
	auth=$(echo "$user:$pass" | base64 -w 0)

	cat << EOF > $HDCI_FOLDER/registry-auth/watchtower/config.json
{
	"auths": {
		"localhost:5000": {
			"auth": "$auth"
		},
		"registry.$1": {
			"auth": "$auth"
		}
	}
}
EOF
}

PASSWORD_LENGTH=64

generate_secret() {
	current=$PASSWORD_LENGTH
	if [ ! -z "$1" ]; then
		current=$1
	fi
	openssl rand -hex $current
}

if [ -z ${HDCI_FOLDER} ]; then
	echo "HDCI_FOLDER is not set"
	echo "Using default value: /var/lib/hdci"
	HDCI_FOLDER=/var/lib/hdci
fi

if [ $# -ne 7 ]; then
	echo "$0 <DOMAIN_NAME> <GITHUB_USER> <CLOUDFLARE_API_EMAIL> <CLOUDFLARE_API_KEY> <DRONE_GITHUB_CLIENT_ID> <DRONE_GITHUB_CLIENT_SECRET> <GITHUB_FILTERING>"
	echo "GITHUB_FILTERING can either be users or orgs separated by a comma"
	echo "If GITHUB_FILTERING is empty, all users and orgs will be allowed this is VERY DANGEROUS"
	exit 1
fi

cloudflare_trusted_ipv4=$(curl -s https://www.cloudflare.com/ips-v4 | tr '\n' ',')
cloudflare_trusted_ipv6=$(curl -s https://www.cloudflare.com/ips-v6 | tr '\n' ',')
cloudflare_trusted_ips="$cloudflare_trusted_ipv4,$cloudflare_trusted_ipv6"
cloudflare_trusted_ips=$(echo $cloudflare_trusted_ips | sed 's/,$//g' | sed 's/,,/,/g' | sed 's/\//\\\//g')

hdci_folder_sed_compliant=$(echo $HDCI_FOLDER | sed 's/\//\\\//g')

cat .env.example | \
	sed "s/{{DOMAIN}}/$1/g" | \
	sed "s/{{GITHUB_USER}}/$2/g" | \
	sed "s/{{CLOUDFLARE_API_EMAIL}}/$3/g" | \
	sed "s/{{CLOUDFLARE_API_KEY}}/$4/g" | \
	sed "s/{{DRONE_GITHUB_CLIENT_ID}}/$5/g" | \
	sed "s/{{DRONE_GITHUB_CLIENT_SECRET}}/$6/g" | \
	sed "s/{{DRONE_RPC_SECRET}}/$(generate_secret 32)/g" | \
	sed "s/{{GITHUB_FILTERING}}/$7/g" | \
	sed "s/{{DRONE_DATABASE_SECRET}}/$(generate_secret 32)/g" | \
	sed "s/{{CLOUDFLARE_TRUSTED_IPS}}/$cloudflare_trusted_ips/g" | \
	sed "s/{{HDCI_FOLDER}}/$hdci_folder_sed_compliant/g" > .env

if should_generate_registry_secrets; then
	generate_registry_secrets $1
else
	echo "Skipping registry secrets generation"
fi
