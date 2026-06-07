# Examples

Concrete, runnable demonstrations of the Noethrion protocol primitives. If the [Whitepaper](docs/whitepaper.html) tells you *why*, and the [Internet-Draft](spec/noethrion-attestation-v0.1.md) tells you *what*, this directory tells you *how*.

Two flavors, in increasing order of integration depth:

## 1. End-to-end lifecycle ([`examples/lifecycle/`](examples/lifecycle/))

Seven numbered files that walk the full protocol from device-key generation to off-chain verification. Run them in order on a local development environment (Anvil + Foundry + Python). At the end you will have:

- A device with an ECDSA P-256 keypair (software stand-in for the secure element)
- A signed attestation tuple `(deviceId, timestamp, kWh)`
- A Merkle root committed on-chain by `NoethrionAttester.submitBatch()`
- A finalized batch after the challenge window
- A NOET claim minted to a beneficiary via `NoethrionAttester.claim()`
- An independent off-chain verification that the same attestation was signed by the device

See [`examples/lifecycle/README.md`](examples/lifecycle/README.md) for prerequisites and run order.

## 2. Integrator templates ([`examples/integrators/`](examples/integrators/))

Drop-in starting points for the three likeliest downstream consumers. Copy the file you need, install its dependencies, edit the configuration constants:

- [`python_verifier_library.py`](examples/integrators/python_verifier_library.py) — backend services in Python. Stateless `NoethrionVerifier` class with `.verify()` returning a typed result. Depends on `cryptography` + `pycryptodome`.
- [`javascript_verifier.ts`](examples/integrators/javascript_verifier.ts) — Node 18+ / Cloudflare Workers / AWS Lambda / Deno. Single `verifyAttestation()` function. Depends on `@noble/curves` + `@noble/hashes`. No DOM or browser globals.
- [`solidity_consumer.sol`](examples/integrators/solidity_consumer.sol) — another smart contract on the same chain. Demonstrates how a downstream contract reads `batches(epoch).finalized`, derives the leaf hash, verifies Merkle inclusion, and applies an arbitrary policy. Override `_applyPolicy()` with your own logic.

All three implement the same three protocol checks — signature, Merkle inclusion, finalization — and stop short of caller-specific policy by design.

See [`examples/integrators/README.md`](examples/integrators/README.md) for the rules each template assumes.

## The four-step verification flow (shared by everything above)

| Step | What | Where |
|------|------|-------|
| 1 | Validate the ECDSA P-256 signature on the canonical payload | All three integrator templates |
| 2 | Re-derive the leaf hash from `keccak256(abi.encode(block.chainid, attesterAddress, beneficiary, amount, epoch))` — the `chainId` + Attester address are the domain separator that binds the leaf to this exact deployment (omit them and the proof fails) | All three integrator templates |
| 3 | Replay the Merkle proof against the on-chain committed root | All three integrator templates |
| 4 | Confirm `batches(epoch).finalized == true` on the Attester | Lifecycle steps 5 & 6; Solidity consumer |

Caller-specific policy (timestamp freshness, jurisdiction, allowlists) is **outside** the protocol — the templates leave step 4 + policy to the integrator.

## See also

- [`QUICKSTART.md`](QUICKSTART.md) — five-minute on-ramp
- [`spec/noethrion-attestation-v0.1.md`](spec/noethrion-attestation-v0.1.md) — normative protocol specification
- [`docs/whitepaper.html`](docs/whitepaper.html) — motivation and threat model
- [`tools/`](tools/) — CLI counterparts to the integrator libraries

---

## 🇷🇺 Примеры на русском

Конкретные, runnable демонстрации примитивов протокола Noethrion. Если [Whitepaper](docs/whitepaper.html) говорит *почему*, а [Internet-Draft](spec/noethrion-attestation-v0.1.md) — *что*, то эта директория показывает *как*.

Два формата, в порядке увеличения глубины интеграции:

### 1. End-to-end lifecycle ([`examples/lifecycle/`](examples/lifecycle/))

Семь нумерованных файлов, которые проводят полный flow протокола от device-key generation до off-chain верификации. Запускай по порядку на локальном dev окружении (Anvil + Foundry + Python). В конце у тебя будет:

- Устройство с ECDSA P-256 keypair (software stand-in для secure element)
- Подписанный attestation tuple `(deviceId, timestamp, kWh)`
- Merkle root committed on-chain через `NoethrionAttester.submitBatch()`
- Finalized batch после challenge window
- NOET claim, минченный beneficiary через `NoethrionAttester.claim()`
- Независимая off-chain верификация что аттестация подписана устройством

Подробности (prerequisites, run order, troubleshooting) — [`examples/lifecycle/README.md`](examples/lifecycle/README.md).

### 2. Integrator шаблоны ([`examples/integrators/`](examples/integrators/))

Drop-in starting points для трёх likeliest downstream consumers. Копируй нужный файл, ставь зависимости, правь configuration constants:

- [`python_verifier_library.py`](examples/integrators/python_verifier_library.py) — backend сервисы на Python. Stateless `NoethrionVerifier` класс с `.verify()` возвращающий typed result. Зависит от `cryptography` + `pycryptodome`.
- [`javascript_verifier.ts`](examples/integrators/javascript_verifier.ts) — Node 18+ / Cloudflare Workers / AWS Lambda / Deno. Single `verifyAttestation()` функция. Зависит от `@noble/curves` + `@noble/hashes`. Без DOM или browser globals.
- [`solidity_consumer.sol`](examples/integrators/solidity_consumer.sol) — другой smart contract на той же chain. Демонстрирует как downstream контракт читает `batches(epoch).finalized`, выводит leaf hash, верифицирует Merkle inclusion, и применяет произвольную политику. Override `_applyPolicy()` своей логикой.

Все три реализуют те же три проверки протокола — подпись, Merkle inclusion, finalization — и останавливаются перед caller-specific policy by design.

Подробности — [`examples/integrators/README.md`](examples/integrators/README.md).

### Четыре шага верификации (общие для всех)

| Шаг | Что | Где |
|------|------|-------|
| 1 | Валидация ECDSA P-256 подписи на каноническом payload | Все три integrator шаблона |
| 2 | Re-derive leaf hash из `keccak256(abi.encode(block.chainid, attesterAddress, beneficiary, amount, epoch))` — `chainId` + адрес Attester это domain separator, привязывающий leaf к конкретному деплою (без них proof не сойдётся) | Все три integrator шаблона |
| 3 | Replay Merkle proof против on-chain committed root | Все три integrator шаблона |
| 4 | Подтверждение `batches(epoch).finalized == true` на Attester | Lifecycle шаги 5 и 6; Solidity consumer |

Caller-specific policy (timestamp freshness, jurisdiction, allowlists) — **вне** протокола; шаблоны оставляют шаг 4 + policy на integrator.

### См. также

- [`QUICKSTART.md`](QUICKSTART.md) — пятиминутная on-ramp
- [`spec/noethrion-attestation-v0.1.md`](spec/noethrion-attestation-v0.1.md) — нормативная спецификация
- [`docs/whitepaper.html`](docs/whitepaper.html) — мотивация и threat model
- [`tools/`](tools/) — CLI аналоги integrator библиотек
