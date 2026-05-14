# 01 · Generate a device key

The protocol's hardware Attester binds an ECDSA P-256 key to a secure element. For local development we substitute a software key — same curve, same signature format, same downstream verification path. Production deployments replace this step with a Common Criteria EAL5+ secure element provisioning ceremony (out of scope for the lifecycle examples).

## Command

From the repository root:

```bash
python3 tools/provision_atecc.py generate-key --out examples/lifecycle/attester.key
```

## Expected output

```
private key written to examples/lifecycle/attester.key    (chmod 600)
public  key written to examples/lifecycle/attester.key.pub
```

Two files appear in this directory:

- `attester.key` — PKCS#8 PEM private key. Permissions are 0600. **Do not commit this file.** It is ignored by `.gitignore` at the repo root.
- `attester.key.pub` — SubjectPublicKeyInfo PEM. This is the key you would register with an Endorser and embed in the on-chain device registry.

## Inspect the public key

```bash
python3 tools/provision_atecc.py show-pubkey --key examples/lifecycle/attester.key
```

Prints the x and y coordinates, the uncompressed `0x04 || x || y` raw form, and the DER encoding. The raw `x || y` form is what an on-chain registry contract would store (64 bytes).

```bash
python3 tools/provision_atecc.py export-onchain --key examples/lifecycle/attester.key
```

Prints just the 64-byte hex string, prefixed with `0x` — ready to paste into a contract call.

## Cleanup before commit

The two key files are private development artifacts. The repository's top-level `.gitignore` covers them by pattern. Verify before any commit:

```bash
git status   # neither attester.key nor attester.key.pub should appear under "Changes"
```

## Next step

[`02_sign_attestation.sh`](./02_sign_attestation.sh) — produce a signed attestation tuple using this key.
