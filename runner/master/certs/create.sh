#!/bin/bash

echo "Moodle Test Runner Certificate Generator"
echo "========================================"
echo ""
echo "Usage: "
echo "create.sh <outputdir> <hostname> [<alternative_hostname> ...]"
echo ""

SCRIPTPATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ "$#" -lt 1 ]
then
  echo "Usage: Must supply the output directory as first param"
  exit 1
fi

CERTDIR="${1}/certificates"

# Remove the first argument.
HOSTNAMES=( "$@" )
HOSTNAMES=( "${HOSTNAMES[@]:1}" )

CACONF="${CERTDIR}/openssl.cnf"
CAKEY="${CERTDIR}/ca/ca.key"
CACERT="${CERTDIR}/ca/ca.pem"

if [ -f "${CAKEY}" ]
then
    echo "CA key already exists, skipping generation"
else
    # Generate the private key for the CA:
    echo "Generating the key and certificate for the CA server"
    mkdir -p "${CERTDIR}/ca"
    mkdir -p "${CERTDIR}/certs"

    # Create the openssl.cnf from the template.
    # Note: We can't just use the template because some of the paths are relative, and we are not guaranteed to be able to access the $ENV.
    echo "Generating the OpenSSL configuration file to ${CACONF}"
    cat "${SCRIPTPATH}/openssl.cnf.template" | sed -e "s|{BASEDIR}|${CERTDIR}|g" > "${CACONF}"

    # Generate the key and certificate for the CA.
    cat <<EOF | openssl req -config ${CACONF} -nodes -new -x509  -keyout "${CAKEY}" -out "${CACERT}"
AU
Western Australia
Perth
Moodle Pty Ltd
Moodle LMS


EOF

    cp "${CACERT}" "${CERTDIR}/certs/ca.crt"

    echo "Generated an OpenSSL Certificate Authority"
    touch "${CERTDIR}/ca/index.txt"
    echo '01' > "${CERTDIR}/ca/serial.txt"
    echo
fi

if [ "$#" -lt 2 ]
then
  echo "Usage: Must supply at least one hostname."
  exit 1
fi

# The first hostname is canonical.
DOMAIN=$2

HOSTKEY="${CERTDIR}/certs/${DOMAIN}.key"
HOSTCSR="${CERTDIR}/certs/${DOMAIN}.csr"
HOSTCRT="${CERTDIR}/certs/${DOMAIN}.crt"
HOSTEXT="${CERTDIR}/certs/${DOMAIN}.ext"
HOSTP12="${CERTDIR}/certs/${DOMAIN}.p12"

# Create a private key for the dev site:
echo
echo "Generating a private key for the $DOMAIN dev site"
echo
openssl genrsa -out "${HOSTKEY}" 2048

echo "Generating a CSR for $DOMAIN"
cat <<EOF | openssl req -nodes -new -key "${HOSTKEY}" -out "${HOSTCSR}"
AU
Western Australia
Perth
Moodle Pty Ltd
Moodle LMS


EOF
echo

DNSCOUNT=1
for var in "$HOSTNAMES[@]"
do
    DNS=$(cat <<-EOF
${DNS}
DNS.${DNSCOUNT} = ${var}
EOF
)
    DNSCOUNT=$((DNSCOUNT + 1))
done

cat > "${HOSTEXT}" << EOF
[ req ]
default_bits       = 2048
default_keyfile    = ${HOSTKEY}
distinguished_name = server_distinguished_name
req_extensions     = server_req_extensions
string_mask        = utf8only

[ server_distinguished_name ]

countryName         = Country Name (2 letter code)
countryName_default = AU

stateOrProvinceName         = State or Province Name (full name)
stateOrProvinceName_default = Western Australia

localityName                = Locality Name (eg, city)
localityName_default        = Perth

organizationName            = Organization Name (eg, company)
organizationName_default    = Moodle Pty Ltd

organizationalUnitName         = Organizational Unit (eg, division)
organizationalUnitName_default = Moodle LMS

commonName         = Common Name (e.g. server FQDN or YOUR name)
commonName_default = ${DOMAIN}

emailAddress         = Email Address
emailAddress_default = moodle@example.com

[ server_req_extensions ]
subjectKeyIdentifier    = hash
basicConstraints        = CA:FALSE
keyUsage                = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName          = @alternate_names
[ alternate_names ]
$DNS
EOF

#Next run the command to create the certificate: using our CSR, the CA private key, the CA certificate, and the config file:
echo "Generating a certificate for $DOMAIN"
cat <<EOF | openssl req -config "${HOSTEXT}" -newkey rsa:2048 -sha256 -nodes -out "${HOSTCSR}" -outform PEM
AU
Western Australia
Perth
Moodle Pty Ltd
Moodle LMS


EOF
echo

echo "Signing the request"
openssl ca -batch -config "${CACONF}" -policy signing_policy -extensions signing_req -out "${HOSTCRT}" -infiles "${HOSTCSR}"

echo "Generating p12 certificate"
openssl pkcs12 -export -out "${HOSTP12}" -inkey "${HOSTKEY}" -in "${HOSTCRT}" -passout pass:
