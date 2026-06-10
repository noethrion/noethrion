# Quickstart

Five-minute on-ramp for engineers and reviewers who just landed on the Noethrion repository.

If you are not an engineer, the more readable entry points are the [Whitepaper](docs/whitepaper.html), the [Constitution](docs/constitution.html), and the [project website](https://noethrion.com).

---

## 1. What this is, in one paragraph

Noethrion is an open standard for hardware-attested verification of electricity generation. A secure element next to a kilowatt-hour meter signs the tuple `(kWh, timestamp, deviceID)` with an ECDSA P-256 key that never leaves the chip. The signatures aggregate into Merkle trees, the roots commit to a public settlement layer, and anyone with the device's endorsed public key can independently verify any single attestation in seconds. The project is a standards body (modeled on Linux Foundation / IETF / ICANN), not a company — the protocol specification is open under MIT and intended to remain that way.

The protocol primitive: **1 NOET = 1 verified kilowatt-hour.**

---

## 2. Repository tour (60 seconds)

```
noethrion/
├── README.md             ← project overview (start here if you skipped the website)
├── docs/                 ← whitepaper, constitution, brand book, landing page
├── spec/                 ← IETF-style protocol specifications (see noethrion-attestation-v0.1.md)
├── contracts/            ← Foundry-based smart contracts (Solidity 0.8.24)
├── firmware/             ← ESP32 + ATECC608B reference firmware (PlatformIO, C++17)
├── assets/logos/         ← brand SVG assets (D / E / F / G categories)
├── CONTRIBUTING.md       ← how to send a pull request
├── SECURITY.md           ← responsible disclosure policy
└── .github/workflows/    ← CI (lint + tests) and Cloudflare Pages deploy
```

The shortest path through the project, if you want to understand it end-to-end, is:

1. `README.md` → architecture intent.
2. `spec/noethrion-attestation-v0.1.md` → protocol mechanics.
3. `contracts/src/NoethrionAttester.sol` and `contracts/src/NoethrionToken.sol` → on-chain semantics.
4. `firmware/src/main.cpp` → device-side semantics.

That sequence is roughly 60 minutes of reading.

---

## 3. Run the smart-contract tests (2 minutes)

You will need [Foundry](https://book.getfoundry.sh/getting-started/installation) installed.

```bash
git clone https://github.com/noethrion/noethrion.git
cd noethrion/contracts
forge install
forge test
```

Expected output: **all tests pass** (currently 127/127 across the unit, security, invariant, deployment-handoff, deployment-validation, and deployment-Timelock suites; plus 25/25 Halmos symbolic checks via `halmos --contract NoethrionAttesterHalmosTest` and `halmos --contract NoethrionTokenHalmosTest`).

Useful follow-ups:

```bash
forge test -vvv                  # verbose traces
forge test --gas-report          # gas usage per function
forge coverage                   # coverage report (text or LCOV)
forge fmt --check                # confirm formatting
```

If any test fails on `main`, that is a bug — please open an issue.

---

## 4. Build the firmware skeleton (5 minutes)

You will need [PlatformIO Core](https://docs.platformio.org/en/latest/core/installation/index.html) installed (`pip install platformio` is the fastest path on most systems).

```bash
cd noethrion/firmware
pio run                          # builds, downloads dependencies on first run
pio run -t upload                # flashes an attached ESP32 (auto-detects port)
pio device monitor -b 115200     # opens serial console
```

The current skeleton is a **probe-only stub**: it initializes the I²C bus, attempts to handshake with an ATECC608B secure element, prints its serial number and zone-lock state, and emits a placeholder JSON attestation tuple over serial every ten seconds. Real meter integration, real ECDSA signing inside the secure element, and upstream publication are the next firmware milestone.

A board without an ATECC608B attached still flashes and runs — the skeleton degrades gracefully to "no-secure-element" mode. Hardware bring-up details, including the bill of materials, pinout, and provisioning workflow, are documented in [`firmware/README.md`](firmware/README.md).

---

## 5. Verify an attestation by hand (10 minutes)

Once a device produces a real attestation (forthcoming milestone), independent verification is straightforward in any language. The flow is:

1. Receive the attestation token (CBOR bytes) and its Merkle inclusion proof (a list of sibling hashes).
2. Compute the SHA-256 leaf hash from the canonical CBOR encoding.
3. Apply the inclusion proof to derive the candidate Merkle root.
4. Read the on-chain commitment for the attestation's epoch from `NoethrionAttester.batches(epoch)`.
5. Confirm the candidate root matches the committed root and that the batch is finalized (challenge window elapsed).
6. Validate the ECDSA P-256 signature against the device's endorsed public key.

A reference implementation, `tools/verify_attestation.py`, lives in the [`tools/`](tools/) directory.

The protocol specification — `spec/noethrion-attestation-v0.1.md`, Sections 4 through 7 — defines every step normatively.

---

## 6. Where to look next

| If you are interested in… | Read |
|---|---|
| The protocol mechanics (signing, batching, settlement) | `spec/noethrion-attestation-v0.1.md` |
| End-to-end runnable examples and integrator templates | `EXAMPLES.md` |
| The economic and governance design | `docs/constitution.html` |
| The motivation, threat model, and prior art | `docs/whitepaper.html` |
| The on-chain contract surface | `contracts/src/NoethrionAttester.sol`, `contracts/src/NoethrionToken.sol` |
| The device-side firmware | `firmware/src/main.cpp`, `firmware/README.md` |
| Brand and visual identity | `docs/brand-book-v0.3.html` |
| How to send a pull request | `CONTRIBUTING.md` |

The hardest open problems at the moment, and the ones where reviewer feedback is most valued, are:

1. **Post-quantum migration plan** (Section 5.2 of the I-D) — how to rotate signature algorithms without invalidating historical attestations.
2. **Endorser governance** (Section 7 of the I-D) — what federation of certification authorities can credibly endorse device public keys at scale.
3. **Production threshold value selection** — the v0.2 contract ships with admin-configurable `threshold` and supports m-of-n quorum (ADR-006). Choosing the right `m` for mainnet, and Endorser federation onboarding, are the remaining governance questions on this axis.

If you can find a hole in any of these, please open a Discussion or send an email to `team@noethrion.com`. We would rather learn that the design is wrong now than after deployment.

---

## 🇷🇺 Quickstart на русском

Пятиминутная on-ramp для инженеров и ревьюеров, только что попавших в репозиторий Noethrion.

Если ты не инженер — более удобные точки входа: [Whitepaper](docs/whitepaper.html), [Constitution](docs/constitution.html), [сайт проекта](https://noethrion.com).

### 1. Что это такое — одним абзацем

Noethrion — открытый стандарт аппаратно-подтверждённой верификации генерации электроэнергии. Secure element рядом со счётчиком киловатт-часов подписывает кортеж `(кВт·ч, timestamp, deviceID)` через ECDSA P-256 ключ, который никогда не покидает чип. Подписи агрегируются в Merkle деревья, корни анкорятся в публичный settlement layer, и любой с публичным ключом устройства может independently верифицировать любую отдельную аттестацию за секунды. Проект — standards body (по модели Linux Foundation / IETF / ICANN), не компания — спецификация протокола под MIT и таковой остаётся.

Примитив протокола: **1 NOET = 1 верифицированный киловатт-час.**

### 2. Тур по репозиторию (60 секунд)

```
noethrion/
├── README.md             общий обзор проекта
├── docs/                 whitepaper, constitution, brand book, ADRs, landing page
├── spec/                 IETF-style спецификация протокола
├── contracts/            Foundry — NoethrionAttester + NoethrionToken (Solidity 0.8.24)
├── firmware/             ESP32 + ATECC608B reference firmware (PlatformIO)
├── examples/             end-to-end lifecycle + integrator templates
├── tools/                Python CLI — provision, verify, render assets
├── assets/logos/         SVG brand assets (D / E / F / G categories)
├── CONTRIBUTING.md       как отправить pull request
├── SECURITY.md           responsible disclosure
└── .github/workflows/    CI (lint + Foundry тесты) + Cloudflare Pages deploy
```

Кратчайший путь end-to-end понимания проекта, примерно 60 минут чтения:

1. `README.md` → архитектурное намерение
2. `spec/noethrion-attestation-v0.1.md` → механика протокола
3. `contracts/src/NoethrionAttester.sol` + `contracts/src/NoethrionToken.sol` → on-chain семантика
4. `firmware/src/main.cpp` → device-side семантика

### 3. Запуск smart-contract тестов (2 минуты)

Требуется [Foundry](https://book.getfoundry.sh/getting-started/installation).

```bash
git clone https://github.com/noethrion/noethrion.git
cd noethrion/contracts
forge install
forge test
```

Ожидаемый вывод: **все тесты pass** (на данный момент 127/127 forge tests + 25/25 Halmos symbolic proofs across двух suites — `NoethrionAttester` и `NoethrionToken`).

Полезные follow-ups:

```bash
forge test -vvv                  # verbose traces
forge test --gas-report          # газ per function
forge coverage                   # покрытие
forge fmt --check                # форматирование
```

Если на `main` падает любой тест — это баг, открой issue.

### 4. Сборка reference firmware (5 минут)

Требуется [PlatformIO Core](https://docs.platformio.org/en/latest/core/installation/index.html) — `pip install platformio` на большинстве систем.

```bash
cd noethrion/firmware
pio run                          # сборка, на первом запуске тянет зависимости
pio run -t upload                # прошивка подключённого ESP32 (автоопределение порта)
pio device monitor -b 115200     # открывает serial консоль
```

Текущий skeleton — **probe-only стаб**: инициализирует I²C, пытается handshake с ATECC608B, печатает его serial number и состояние zone locks, и каждые 10 секунд эмитит placeholder JSON tuple. Реальная интеграция со счётчиком, реальное подписывание ECDSA, и upstream публикация — это следующий firmware milestone.

Плата без ATECC608B всё равно прошивается и работает — skeleton gracefully падает в "no-secure-element" mode. Детали bring-up: [`firmware/README.md`](firmware/README.md).

### 5. Верификация аттестации вручную (10 минут)

Когда у тебя есть реальная аттестация (предстоит в следующих milestone), независимая верификация прямолинейна на любом языке. Flow:

1. Получи attestation token (CBOR байты) и Merkle inclusion proof (список sibling хэшей)
2. Посчитай SHA-256 leaf хэш канонического CBOR
3. Применяй inclusion proof чтобы вывести candidate root
4. Прочитай on-chain commitment для эпохи через `NoethrionAttester.batches(epoch)`
5. Подтверди что candidate root совпадает с committed root и что batch finalized
6. Валидируй ECDSA P-256 подпись против endorsed публичного ключа устройства

Reference implementation `tools/verify_attestation.py` живёт в директории [`tools/`](tools/).

Спецификация протокола — `spec/noethrion-attestation-v0.1.md` секции 4-7 — определяет каждый шаг normatively.

### 6. Куда смотреть дальше

| Если интересно… | Читай |
|---|---|
| Механика протокола (signing, batching, settlement) | `spec/noethrion-attestation-v0.1.md` |
| End-to-end runnable примеры + integrator шаблоны | `EXAMPLES.md` |
| Экономика и governance дизайн | `docs/constitution.html` |
| Мотивация, threat model, prior art | `docs/whitepaper.html` |
| On-chain контрактная поверхность | `contracts/src/NoethrionAttester.sol`, `contracts/src/NoethrionToken.sol` |
| Device-side firmware | `firmware/src/main.cpp`, `firmware/README.md` |
| Бренд и визуальная identity | `docs/brand-book-v0.3.html` |
| Как отправить PR | `CONTRIBUTING.md` |

Самые трудные open problems на данный момент, и те где reviewer feedback наиболее ценен:

1. **План post-quantum миграции** (Section 5.2 I-D) — как ротировать signature алгоритмы без инвалидации исторических аттестаций
2. **Endorser governance** (Section 7 I-D) — какая федерация certification authorities может credibly endorse публичные ключи устройств на масштабе
3. **Выбор production threshold** — v0.2 контракт уже реализует admin-configurable `threshold` + m-of-n quorum (ADR-006). Выбор правильного `m` для mainnet, и Endorser federation onboarding — оставшиеся governance вопросы на этой оси.

Если найдёшь дыру в любом из этих — открой Discussion или email на `team@noethrion.com`. Мы предпочтём узнать что дизайн неправильный сейчас, чем после deployment.

---

*η = E_useful / E_total*
