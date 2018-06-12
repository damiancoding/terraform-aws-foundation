{
    "CN": "${DISCOURSE_URL}",
    "hosts": [
        "${DISCOURSE_URL}",
        "${REGISTRY_URL}"
    ],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "O": "${ORGANIZATION}",
            "C": "${COUNTRY}",
            "ST": "${STATE}",
            "L": "${LOCALITY}"
        }
    ]
}
