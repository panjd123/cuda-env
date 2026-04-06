# Encrypted Codex Config

This directory is for the encrypted, repo-safe Codex config bundle.

Expected file:

```text
.codex.encrypted/config.tar.gz.enc
```

Generate or refresh it from your local plaintext `.codex/` directory:

```bash
export CODEX_CONFIG_PASSPHRASE='choose-a-long-passphrase'
./compose.sh codex-seal
```

Restore the local plaintext `.codex/` directory from the encrypted bundle:

```bash
export CODEX_CONFIG_PASSPHRASE='choose-a-long-passphrase'
./compose.sh codex-unseal
```
