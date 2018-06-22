# FIXME: remove this completely. gitlab has a 'git' user for using git with
# repositories hosted on gitlab via ssh. This doesn't apply to Discourse.
Host ${DISCOURSE_NAME}.${DNS_ZONE_NAME}
    identityfile ${PWD}/id_rsa
    user git
