#!/usr/bin/env bash
#
# configure-strongswan.sh
#
# Runs strongSwan's ./configure with an explicit plugin set: every plugin is
# listed as Allow (--enable) or Deny (--disable), so a new upstream default
# never silently changes what ends up in the image. Run from the extracted
# source tree. Extra arguments are appended for local experiments.
#
# Plugins removed upstream in 6.1.0 (af-alg, blowfish, duplicheck, gcrypt,
# keychain, led, medcli/medsrv, padlock, smp, soup, tnc-ifmap, tnccs-11,
# tnccs-dynamic, ...) are no longer listed.
#
# pkcs12 is intentionally NOT enabled: it force-enables the rc2 plugin and all
# credentials are delivered as PEM.
#
# Network helper plugins (bypass-lan, farp, forecast, connmark) are disabled:
# a road-warrior gateway does not need them, and bypass-lan reacts to the
# address/route changes during shutdown, which can deadlock charon's shutdown
# (shunt manager waits for an install a cancelled job never finishes).

# =====================================================================
# CRYPTO INVARIANT -- read before editing any --disable-* below
# =====================================================================
# openssl is the SOLE crypto provider. All primitives the proposals
# negotiate (AES-GCM, SHA-2, X25519/ECP, Ed25519) come from libcrypto via
# --enable-openssl, NOT from strongSwan's native plugins.
#
# Therefore --disable-aes / -gcm / -sha1 / -sha2 / -hmac / -gmp etc. only
# disable REDUNDANT software implementations -- they do NOT prohibit the
# algorithm (SHA-1 is still available from openssl, e.g. for NAT detection).
#
# Removing --enable-openssl breaks every SA (no backend left to satisfy
# the proposals).
# =====================================================================

set -euo pipefail

FLAGS=()

# ---------------------------------------------------------------------
# Install paths
# --libexecdir=/usr/lib keeps charon at /usr/lib/ipsec/charon (entrypoint.sh)
# ---------------------------------------------------------------------
FLAGS+=(--prefix=/usr)
FLAGS+=(--sysconfdir=/etc)
FLAGS+=(--localstatedir=/var)
FLAGS+=(--libexecdir=/usr/lib)

# Container-managed init; no systemd integration.
FLAGS+=(--disable-systemd)

# =====================================================================
# libstrongswan plugins
# =====================================================================

# --- Certificate handling --------------------------------------------
FLAGS+=(--disable-acert)
FLAGS+=(--enable-constraints)
FLAGS+=(--disable-dnskey)
FLAGS+=(--enable-revocation)
FLAGS+=(--enable-x509)

# --- Credential store ------------------------------------------------
FLAGS+=(--disable-agent)

# --- Crypto backend --------------------------------------------------
FLAGS+=(--disable-botan)
FLAGS+=(--enable-openssl)
FLAGS+=(--disable-wolfssl)

# --- Ciphers (redundant with openssl) --------------------------------
FLAGS+=(--disable-aes)
FLAGS+=(--disable-aesni)
FLAGS+=(--disable-chapoly)
FLAGS+=(--disable-des)
FLAGS+=(--disable-rc2)

# --- Cipher modes (redundant with openssl) ---------------------------
FLAGS+=(--disable-ccm)
FLAGS+=(--disable-cmac)
FLAGS+=(--disable-ctr)
FLAGS+=(--disable-gcm)
FLAGS+=(--disable-xcbc)

# --- Hashes ----------------------------------------------------------
FLAGS+=(--disable-md4)
FLAGS+=(--disable-md5)
FLAGS+=(--disable-sha1)
FLAGS+=(--disable-sha2)
FLAGS+=(--disable-sha3)

# --- KDF / PRF / MAC -------------------------------------------------
FLAGS+=(--disable-fips-prf)
FLAGS+=(--disable-hmac)
FLAGS+=(--enable-kdf)
FLAGS+=(--disable-mgf1)

# --- Public key / key exchange ---------------------------------------
FLAGS+=(--enable-curve25519)
FLAGS+=(--disable-gmp)
FLAGS+=(--enable-ml)                # ML-KEM (post-quantum key exchange)

# --- RNG -------------------------------------------------------------
FLAGS+=(--enable-drbg)
FLAGS+=(--enable-nonce)
FLAGS+=(--enable-random)
FLAGS+=(--disable-rdrand)

# --- Databases -------------------------------------------------------
FLAGS+=(--disable-mysql)
FLAGS+=(--disable-sqlite)

# --- Encoding / parsing ----------------------------------------------
FLAGS+=(--enable-pem)
FLAGS+=(--disable-pgp)
FLAGS+=(--enable-pkcs1)
FLAGS+=(--disable-pkcs12)           # forces rc2; credentials are PEM
FLAGS+=(--enable-pkcs7)
FLAGS+=(--enable-pkcs8)
FLAGS+=(--enable-pubkey)
FLAGS+=(--disable-sshkey)

# --- Fetchers --------------------------------------------------------
FLAGS+=(--enable-curl)
FLAGS+=(--enable-files)
FLAGS+=(--disable-ldap)
FLAGS+=(--disable-unbound)
FLAGS+=(--disable-winhttp)

# --- PKI / OCSP ------------------------------------------------------
FLAGS+=(--disable-openxpki)

# --- Test ------------------------------------------------------------
FLAGS+=(--disable-test-vectors)

# =====================================================================
# libcharon plugins
# =====================================================================

# --- Certificate / auth helpers --------------------------------------
FLAGS+=(--enable-certexpire)
FLAGS+=(--disable-coupling)
FLAGS+=(--disable-dnscert)
FLAGS+=(--disable-ext-auth)
FLAGS+=(--disable-ipseckey)
FLAGS+=(--disable-systime-fix)
FLAGS+=(--disable-whitelist)

# --- EAP methods -----------------------------------------------------
FLAGS+=(--disable-eap-aka)
FLAGS+=(--disable-eap-aka-3gpp)
FLAGS+=(--disable-eap-aka-3gpp2)
FLAGS+=(--disable-eap-dynamic)
FLAGS+=(--disable-eap-gtc)
FLAGS+=(--enable-eap-identity)
FLAGS+=(--disable-eap-md5)          # MD5
FLAGS+=(--disable-eap-mschapv2)     # MD4/MD5 dependency
FLAGS+=(--disable-eap-peap)
FLAGS+=(--enable-eap-radius)
FLAGS+=(--disable-eap-sim)
FLAGS+=(--disable-eap-sim-file)
FLAGS+=(--disable-eap-sim-pcsc)
FLAGS+=(--disable-eap-simaka-pseudonym)
FLAGS+=(--disable-eap-simaka-reauth)
FLAGS+=(--disable-eap-simaka-sql)
FLAGS+=(--enable-eap-tls)
FLAGS+=(--disable-eap-tnc)
FLAGS+=(--disable-eap-ttls)

# --- IKE / network attributes ----------------------------------------
FLAGS+=(--disable-addrblock)
FLAGS+=(--enable-attr)
FLAGS+=(--disable-attr-sql)
FLAGS+=(--disable-bypass-lan)       # see header: shutdown deadlock risk
FLAGS+=(--disable-connmark)
FLAGS+=(--disable-dhcp)
FLAGS+=(--disable-farp)
FLAGS+=(--disable-forecast)
FLAGS+=(--disable-lookip)
FLAGS+=(--disable-p-cscf)
FLAGS+=(--enable-resolve)
FLAGS+=(--disable-unity)            # IKEv1
FLAGS+=(--enable-updown)
FLAGS+=(--enable-vici)

# --- Kernel interface ------------------------------------------------
FLAGS+=(--disable-kernel-iph)
FLAGS+=(--enable-kernel-netlink)
FLAGS+=(--disable-kernel-pfkey)
FLAGS+=(--disable-kernel-pfroute)
FLAGS+=(--disable-kernel-wfp)
FLAGS+=(--disable-kernel-libipsec)  # collides with the host XFRM stack

# --- Management / control --------------------------------------------
FLAGS+=(--disable-stroke)           # legacy ipsec.conf/IKEv1 interface
FLAGS+=(--enable-swanctl)

# --- Monitoring / debug ----------------------------------------------
FLAGS+=(--enable-counters)
FLAGS+=(--disable-error-notify)
FLAGS+=(--disable-load-tester)
FLAGS+=(--disable-radattr)
FLAGS+=(--disable-save-keys)        # would defeat PFS

# --- Platform specific -----------------------------------------------
FLAGS+=(--disable-android-log)
FLAGS+=(--disable-osx-attr)

# --- Sockets ---------------------------------------------------------
FLAGS+=(--enable-socket-default)
FLAGS+=(--disable-socket-dynamic)
FLAGS+=(--disable-socket-win)

# --- TNC -------------------------------------------------------------
FLAGS+=(--disable-tnc-pdp)
FLAGS+=(--disable-tnc-imc)
FLAGS+=(--disable-tnc-imv)
FLAGS+=(--disable-tnccs-20)

# --- XAuth (IKEv1 only) ----------------------------------------------
FLAGS+=(--disable-xauth-eap)
FLAGS+=(--disable-xauth-generic)
FLAGS+=(--disable-xauth-noauth)
FLAGS+=(--disable-xauth-pam)

# `exec` so configure's exit status is the script's exit status.
exec ./configure "${FLAGS[@]}" "$@"
