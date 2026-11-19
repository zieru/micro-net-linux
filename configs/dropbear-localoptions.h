#ifndef DROPBEAR_LOCALOPTIONS_H
#define DROPBEAR_LOCALOPTIONS_H

/* Optimize binary and runtime memory footprint for 128 MB RAM */
#define DROPBEAR_SMALL_CODE 1
#define DO_HOST_LOOKUP 0

/* Modern fast host key only (Ed25519) */
#define DROPBEAR_ED25519 1
#define DROPBEAR_ECDSA 0
#define DROPBEAR_RSA 0
#define DROPBEAR_DSS 0

/* Modern fast ciphers & MACs */
#define DROPBEAR_CHACHA20POLY1305 1
#define DROPBEAR_AES128 1
#define DROPBEAR_AES256 0
#define DROPBEAR_3DES 0
#define DROPBEAR_ENABLE_GCM_MODE 1
#define DROPBEAR_ENABLE_CBC_MODE 0
#define DROPBEAR_SHA1_HMAC 0

/* Key exchange */
#define DROPBEAR_CURVE25519 1
#define DROPBEAR_DH_GROUP14_SHA256 1
#define DROPBEAR_DH_GROUP1 0

/* Auth & forwarding */
#define DROPBEAR_SVR_PASSWORD_AUTH 1
#define DROPBEAR_SVR_PUBKEY_AUTH 1
#define DROPBEAR_SVR_AGENTFWD 0
#define DROPBEAR_X11FWD 0

/* Disable unused features */
#define DROPBEAR_SFTPSERVER 0
#define DROPBEAR_CLI_NETCAT 0

/* Tighter per-connection limits & window sizes */
#define MAX_UNAUTH_PER_IP 2
#define MAX_UNAUTH_CLIENTS 4
#define DEFAULT_RECV_WINDOW 32768
#define DROPBEAR_PATH_SSH_PROGRAM "/usr/bin/dbclient"

#endif /* DROPBEAR_LOCALOPTIONS_H */
