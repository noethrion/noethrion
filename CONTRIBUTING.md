# Contributing to Noethrion / Контрибьюшен в Noethrion

🇬🇧 [English](#-english) · 🇷🇺 [Русский](#-русский)

---

## 🇬🇧 English

Thank you for considering contributing to Noethrion. This is an open, long-term protocol effort that depends on contributions from many people across many disciplines. We welcome you.

### Before you start

1. Read the [Whitepaper](docs/whitepaper.html) — it explains what we're building and why.
2. Read the [Constitution](docs/constitution.html) — it explains how we govern.
3. Read the [Code of Conduct](CODE_OF_CONDUCT.md) — it sets behavioral expectations.

If you disagree with the technical direction or the governance model, open a [Discussion](https://github.com/noethrion/noethrion/discussions) before writing code. We'd rather have the conversation early.

### Ways to contribute

#### 1. Code contributions

We accept contributions in these areas:

- **Smart contracts** (Solidity, Foundry) — `contracts/`
- **Firmware** (C/C++, ESP-IDF, PlatformIO) — `firmware/`
- **Specification drafts** (Markdown, RFC-style) — `spec/`
- **Reference clients** (any language) — separate repos welcomed
- **Tooling** (verification scripts, dashboards, etc.)

#### 2. Documentation

- Translation of existing documents (especially: Spanish, Mandarin, German, Japanese)
- Tutorial articles
- Diagram improvements
- Typo fixes (yes, even small ones — they matter)

#### 3. Specification feedback

The protocol specification is in active development. We need critical reviewers. If you find a flaw — open an Issue.

#### 4. Hardware testing

If you have access to:
- Smart electricity meters (residential or commercial)
- Solar inverters
- Industrial power monitoring equipment
- Secure element development kits

...we want to hear from you. Email team@noethrion.com.

#### 5. Standards body engagement

If you participate in IETF, IEEE, IEC, or similar — we are seeking liaisons.

### Workflow

#### For small changes (typo, doc clarification, single function fix)

1. Fork the repo
2. Create a branch: `git checkout -b fix/short-description`
3. Make your changes
4. Commit with a clear message (see commit conventions below)
5. Push to your fork
6. Open a Pull Request

#### For larger changes (new features, architectural changes)

1. **Open an Issue first** describing what you want to do
2. Wait for maintainer feedback (within 7 days)
3. If approved, proceed with the workflow above
4. Reference the Issue in your PR

### Commit conventions

We use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat(scope): brief description
fix(scope): brief description
docs(scope): brief description
test(scope): brief description
refactor(scope): brief description
chore(scope): brief description
```

Examples:
- `feat(contracts): add Merkle root verification function`
- `fix(firmware): correct I2C timing for ATECC608B`
- `docs(spec): clarify attestation interval requirements`
- `chore(deps): bump foundry to v0.2.0`

### Code style

#### Solidity
- Solidity ^0.8.24
- Use `forge fmt` before committing
- 4-space indentation
- NatSpec comments on all public functions
- Coverage target: >95% for production contracts (current: Attester 100/98.72/95.24/100, Token 100/100/100/100)

### Verification bar (do not regress)

Before opening a PR that touches `contracts/`, confirm locally:

- `forge test` passes (127 tests at the audit-target SHA — any new test added MUST keep all prior tests passing)
- `halmos --contract NoethrionAttesterHalmosTest` and `halmos --contract NoethrionTokenHalmosTest` both pass (25 symbolic proofs total — every public function on both contracts has at least one symbolic property pinned, this bar MUST hold)
- `./tools/run_lifecycle.sh` and `THRESHOLD=3 ./tools/run_lifecycle.sh` both print `LIFECYCLE PASS` (end-to-end smoke on a fresh Anvil; matrix CI re-runs both on every push)
- Any new public function on `NoethrionAttester` or `NoethrionToken` MUST add at least one symbolic property to the corresponding `*.halmos.t.sol` suite — the "every public function symbolically pinned" property is load-bearing for the pre-audit posture and an external auditor will check it explicitly
- Any new `AttestationBatch` struct field MUST update the 7+ destructure call sites across the test suite + `examples/lifecycle/05_finalize_batch.s.sol` + `examples/integrators/solidity_consumer.sol` interface — see commit `d190411` for the pattern when the `challengeWindowAtPropose` field was added

CI re-runs `forge test`, `halmos`, `slither`, and `lifecycle-smoke` on every push to `main`. A red CI on `main` is a regression and gets reverted, not patched-forward.

#### C/C++ (firmware)
- C++17
- C++ Core Guidelines (isocpp.github.io/CppCoreGuidelines)
- Doxygen comments on public functions
- No dynamic allocation in critical paths

#### Markdown / Documentation
- Sentence case for headings (not Title Case)
- Bilingual where possible (EN + RU at minimum)
- Line length: soft 100, hard 120
- No trailing whitespace

### Developer Certificate of Origin (DCO)

By contributing, you certify that you have the right to submit your contribution under the project's license. Add a `Signed-off-by` line to your commits:

```
git commit -s -m "feat(contracts): add new function"
```

This will append `Signed-off-by: Your Name <your@email.com>` automatically.

The full DCO text: [developercertificate.org](https://developercertificate.org/)

### Pull Request review

- Maintainers will review within 7 days
- We may request changes — this is normal
- Don't take it personally; it's about the code, not you
- We aim to be specific and constructive

### Communication

- **Discussions:** for questions, ideas, design conversations
- **Issues:** for bugs and concrete feature requests
- **Email:** team@noethrion.com for sensitive matters
- **Security:** security@noethrion.com (see SECURITY.md)

### Recognition

All contributors are listed in our `CONTRIBUTORS.md` (coming soon). Significant contributors may be invited to the Builders House (see Constitution for details).

We do not currently offer monetary compensation for contributions. We may in the future, through grant programs and the Foundation. We will never offer compensation in unreleased token allocations to contributors.

---

## 🇷🇺 Русский

Спасибо что рассматриваете возможность контрибьюшена в Noethrion. Это открытый, долгосрочный протокольный проект, который зависит от вкладов многих людей из разных дисциплин. Мы рады вам.

### Перед тем как начать

1. Прочитайте [Whitepaper](docs/whitepaper.html) — объясняет что и зачем мы строим.
2. Прочитайте [Constitution](docs/constitution.html) — объясняет как мы управляем.
3. Прочитайте [Code of Conduct](CODE_OF_CONDUCT.md) — задаёт поведенческие ожидания.

Если вы не согласны с техническим направлением или governance model — откройте [Discussion](https://github.com/noethrion/noethrion/discussions) до написания кода. Лучше поговорить заранее.

### Способы внести вклад

#### 1. Код

Мы принимаем вклад в эти области:

- **Smart contracts** (Solidity, Foundry) — `contracts/`
- **Firmware** (C/C++, ESP-IDF, PlatformIO) — `firmware/`
- **Спецификация** (Markdown, RFC-style) — `spec/`
- **Reference clients** (любой язык) — отдельные репо приветствуются
- **Tooling** (verification scripts, dashboards, и т.д.)

#### 2. Документация

- Перевод существующих документов (особенно: испанский, мандарин, немецкий, японский)
- Tutorial статьи
- Улучшение диаграмм
- Исправление опечаток (да, даже маленьких — они важны)

#### 3. Обратная связь по спецификации

Спецификация протокола в активной разработке. Нам нужны критические ревьюеры. Если найдёте недостаток — откройте Issue.

#### 4. Hardware testing

Если у вас есть доступ к:
- Smart электросчётчикам (residential или commercial)
- Solar инверторам
- Industrial power monitoring оборудованию
- Secure element development kits

...мы хотим услышать от вас. Email team@noethrion.com.

#### 5. Engagement со standards bodies

Если вы участвуете в IETF, IEEE, IEC или подобных — мы ищем liaisons.

### Workflow

#### Для маленьких изменений (typo, doc clarification, исправление одной функции)

1. Fork репозитория
2. Создайте branch: `git checkout -b fix/short-description`
3. Внесите изменения
4. Commit с понятным message (см. commit conventions ниже)
5. Push в свой fork
6. Откройте Pull Request

#### Для больших изменений (новые features, архитектурные изменения)

1. **Сначала откройте Issue** с описанием что вы хотите сделать
2. Дождитесь обратной связи от maintainers (в течение 7 дней)
3. Если approved, продолжайте по workflow выше
4. Reference Issue в вашем PR

### Commit conventions

Мы используем [Conventional Commits](https://www.conventionalcommits.org/):

```
feat(scope): краткое описание
fix(scope): краткое описание
docs(scope): краткое описание
test(scope): краткое описание
refactor(scope): краткое описание
chore(scope): краткое описание
```

Примеры:
- `feat(contracts): add Merkle root verification function`
- `fix(firmware): correct I2C timing for ATECC608B`
- `docs(spec): clarify attestation interval requirements`
- `chore(deps): bump foundry to v0.2.0`

### Код стайл

#### Solidity
- Solidity ^0.8.24
- Используйте `forge fmt` перед commit
- Отступ 4 пробела
- NatSpec comments на всех public functions
- Coverage target: >95% для production контрактов (текущий: Attester 100/98.72/95.24/100, Token 100/100/100/100)

### Verification bar (не регрессировать)

Перед открытием PR в `contracts/` локально подтверди:

- `forge test` проходит (127 тестов на audit-target SHA — любой новый тест ДОЛЖЕН сохранить прохождение всех предыдущих)
- `halmos --contract NoethrionAttesterHalmosTest` и `halmos --contract NoethrionTokenHalmosTest` оба проходят (25 symbolic proofs всего — каждая публичная функция обоих контрактов имеет хотя бы один pinned symbolic property, эта планка ДОЛЖНА держаться)
- `./tools/run_lifecycle.sh` и `THRESHOLD=3 ./tools/run_lifecycle.sh` оба печатают `LIFECYCLE PASS`
- Любая новая публичная функция на `NoethrionAttester` или `NoethrionToken` ДОЛЖНА добавить хотя бы одну symbolic property в соответствующий `*.halmos.t.sol` — "every public function symbolically pinned" load-bearing для pre-audit posture
- Любое новое поле в struct `AttestationBatch` ДОЛЖНО обновить 7+ destructure call sites через тестовый набор + `examples/lifecycle/05_finalize_batch.s.sol` + интерфейс `examples/integrators/solidity_consumer.sol` — паттерн в commit `d190411`

CI пере-запускает `forge test`, `halmos`, `slither`, и `lifecycle-smoke` на каждый push в `main`. Red CI на `main` — это регрессия и откатывается, не патчится forward.

#### C/C++ (firmware)
- C++17
- C++ Core Guidelines (isocpp.github.io/CppCoreGuidelines)
- Doxygen comments на public functions
- Никакого dynamic allocation в critical paths

#### Markdown / Documentation
- Sentence case для заголовков (не Title Case)
- Bilingual где возможно (EN + RU минимум)
- Длина строки: soft 100, hard 120
- Без trailing whitespace

### Developer Certificate of Origin (DCO)

Контрибьютя, вы подтверждаете что имеете право отправлять свой вклад под лицензией проекта. Добавьте `Signed-off-by` строку в свои commits:

```
git commit -s -m "feat(contracts): add new function"
```

Это автоматически добавит `Signed-off-by: Your Name <your@email.com>`.

Полный DCO текст: [developercertificate.org](https://developercertificate.org/)

### Pull Request review

- Maintainers сделают review в течение 7 дней
- Мы можем запросить изменения — это нормально
- Не принимайте на свой счёт; речь о коде, не о вас
- Мы стараемся быть конкретными и конструктивными

### Коммуникация

- **Discussions:** для вопросов, идей, design разговоров
- **Issues:** для багов и конкретных feature requests
- **Email:** team@noethrion.com для чувствительных вопросов
- **Security:** security@noethrion.com (см. SECURITY.md)

### Признание

Все контрибьюторы перечислены в нашем `CONTRIBUTORS.md` (скоро). Значительные контрибьюторы могут быть приглашены в Builders House (см. Constitution для деталей).

Мы в настоящее время не предлагаем денежной компенсации за вклады. Можем в будущем, через grant programs и Foundation. Мы никогда не будем предлагать компенсацию в нерелизных token allocations контрибьюторам.

---

**Welcome aboard. / Добро пожаловать на борт.**

η = E_useful / E_total
