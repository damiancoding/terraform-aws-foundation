aws acm import-certificate --certificate file://discourse.pem --private-key file://discourse-key.pem --certificate-chain file://ca.pem --region ${REGION} > upload-gen-cert.json
