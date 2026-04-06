# Encrypted Secrets Bundle

This directory is for the repo-safe encrypted host secrets bundle.

Expected file:

```text
.dev-secrets.encrypted/bundle.tar.gz.enc
```

The bundle file is not created automatically. Generate it after you finish updating
your local plaintext `.dev-secrets/` tree.

Generate or refresh it from your local plaintext `.dev-secrets/` directory:

```bash
export DEV_SECRETS_PASSPHRASE='choose-a-long-passphrase'
./compose.sh secrets-seal
```

Restore the local plaintext `.dev-secrets/` directory from the encrypted bundle:

```bash
export DEV_SECRETS_PASSPHRASE='choose-a-long-passphrase'
./compose.sh secrets-unseal
```
