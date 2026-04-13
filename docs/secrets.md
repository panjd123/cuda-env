# Secrets

This repo keeps plaintext secrets out of git while still allowing optional
build-time import into the images.

## Layout

Local plaintext secrets live under:

```text
.dev-secrets/
  claude/
    settings.json
  codex/
    auth.json
    config.toml
  github/
    gh_token
  huggingface/
    token
  ssh/
    id_ed25519
    id_ed25519.pub
    config
    known_hosts
```

Repo-safe encrypted secrets live at:

```text
.dev-secrets.encrypted/bundle.tar.gz.enc
```

Supported import targets inside the images:

- `.dev-secrets/claude/` -> `~/.claude/`
- `.dev-secrets/codex/` -> `~/.codex/`
- `.dev-secrets/github/gh_token` -> `gh auth login --with-token`
- `.dev-secrets/huggingface/token` -> `~/.cache/huggingface/token`
- `.dev-secrets/ssh/` -> `~/.ssh/`

## Workflow

Seal local plaintext secrets into the encrypted bundle:

```bash
export DEV_SECRETS_PASSPHRASE='choose-a-long-passphrase'
./compose.sh secrets-seal
```

Restore plaintext secrets from the encrypted bundle:

```bash
export DEV_SECRETS_PASSPHRASE='choose-a-long-passphrase'
./compose.sh secrets-unseal
```

Build when only the encrypted bundle exists locally:

```bash
export DEV_SECRETS_PASSPHRASE='choose-a-long-passphrase'
./compose.sh build
```

## Resolution Order

During `./compose.sh build`, secrets are resolved in this order:

1. If local plaintext `.dev-secrets/` exists, use it directly.
2. Otherwise, if `.dev-secrets.encrypted/bundle.tar.gz.enc` exists, decrypt it on the host.
3. Otherwise, continue the build without importing any secrets.

## Important Notes

- `.dev-secrets/` is local plaintext and should not be pushed.
- `.dev-secrets.encrypted/bundle.tar.gz.enc` is the commit-safe encrypted bundle.
- `.dockerignore` excludes both `.dev-secrets/` and `.dev-secrets.encrypted/`, so neither plaintext nor encrypted secrets are sent as build context.
- Decryption happens on the host inside `compose.sh`, not inside Docker build and not inside the final image.
- The image does not need `DEV_SECRETS_PASSPHRASE`, and the passphrase is not baked into image layers.
- If `DEV_SECRETS_ARCHIVE_B64` is empty, the image skips all optional secret copy steps.
- Imported directories are set to `0700` and imported files to `0600`.
- If `.dev-secrets/claude/` exists, the build copies it into `~/.claude/`.
- If `.dev-secrets/github/gh_token` exists, the build runs `gh auth login` and writes the authenticated state into `~/.config/gh/`.
- If `.dev-secrets/huggingface/token` exists, the build writes it to the default Hugging Face token path under `~/.cache/huggingface/token`.

## Dotfile Interaction

Both images also install dotfile non-interactively.

Current behavior:

- dotfile manages shell initialization
- dotfile imports `authorized_keys`
- this repo still manages container `sshd_config`
- if `.dev-secrets/ssh/authorized_keys` exists, the later secrets import can overwrite the file written earlier by dotfile
