# Security Policy / Политика безопасности

🇬🇧 [English](#-english) · 🇷🇺 [Русский](#-русский)

---

## 🇬🇧 English

### Reporting a vulnerability

We take security seriously. If you discover a security vulnerability in any part of the Noethrion project — smart contracts, firmware, specification, or supporting infrastructure — please report it responsibly.

**Email:** security@noethrion.com

**PGP key:** Coming soon (will be published before mainnet launch)

### What to include in your report

Please provide as much of the following as you can:

1. **Type of issue** (e.g., reentrancy, integer overflow, key extraction, replay attack)
2. **Affected component** (e.g., NoethrionAttester.sol, ESP32 firmware, spec section 4.2)
3. **Location** (file path, line numbers, commit hash)
4. **Step-by-step reproduction** if possible
5. **Proof of concept** if available (please redact any sensitive data)
6. **Impact assessment** — what could an attacker do?
7. **Suggested fix** if you have one

### What to expect from us

| Stage | Timeline |
|---|---|
| Initial acknowledgment | Within 48 hours |
| Triage and severity assessment | Within 7 days |
| Status updates | At least every 14 days |
| Patch development | Depends on severity (see below) |
| Public disclosure | Coordinated with reporter |

### Severity-based response timelines

We aim to address vulnerabilities according to their severity:

- **Critical** (funds at risk, key extraction, consensus failure): patch within 7 days
- **High** (DoS, significant data exposure): patch within 30 days
- **Medium** (limited exposure, requires unusual conditions): patch within 90 days
- **Low** (theoretical or low-impact issues): patch in next release cycle

### Bug bounty program

We do not currently offer a bug bounty program. We plan to establish one in coordination with platforms like Immunefi after our smart contracts reach v1.0 and complete a formal audit.

In the meantime, all valid reports will be:

- Acknowledged publicly (with reporter's permission) in our security advisories
- Listed in the project's `CONTRIBUTORS.md`
- Considered for retroactive recognition once a bug bounty program launches

### Scope

The following are **in scope** for this policy:

- ✅ Smart contracts in `contracts/src/`
- ✅ Firmware in `firmware/src/`
- ✅ Protocol specification in `spec/`
- ✅ Documentation that could mislead implementers
- ✅ CI/CD workflows that could compromise releases

The following are **out of scope**:

- ❌ Third-party services we don't control (e.g., GitHub itself, Cloudflare)
- ❌ Issues requiring physical access we haven't authorized
- ❌ Social engineering of contributors
- ❌ DoS attacks against our public infrastructure (websites)
- ❌ Issues already publicly disclosed

### Coordinated disclosure

We follow industry-standard coordinated disclosure:

1. Report received privately
2. We confirm and develop a fix
3. Patch is deployed to affected systems
4. Public disclosure with attribution (90 days max from report, sooner if patched)

If you believe a vulnerability is being actively exploited, please indicate this in your report. We will accelerate response.

### Hall of Fame

Vulnerabilities reported responsibly will be acknowledged here (with reporter's permission):

- *No reports yet — be the first*

### Cryptographic primitives

The Noethrion protocol relies on the following cryptographic assumptions. If you can break any of these, you have found a critical vulnerability:

- **ECDSA P-256** (secure element signing)
- **SHA-256** (Merkle tree hashing)
- **Keccak-256** (EVM-compatible hashing)
- **ATECC608B** secure element key isolation
- **Ethereum L2 security model** (EVM-compatible Layer 2, fraud proofs)

Issues with these primitives at the algorithmic level should be reported to the appropriate upstream maintainers (e.g., Microchip, the relevant L2 team). Issues with our implementation of these primitives should be reported to us.

---

## 🇷🇺 Русский

### Сообщение об уязвимости

Мы серьёзно относимся к безопасности. Если вы обнаружили уязвимость безопасности в любой части проекта Noethrion — smart contracts, firmware, спецификации или поддерживающей инфраструктуре — пожалуйста, сообщите об этом ответственно.

**Email:** security@noethrion.com

**PGP key:** Скоро (будет опубликован до mainnet launch)

### Что включить в ваш отчёт

Пожалуйста предоставьте как можно больше следующего:

1. **Тип проблемы** (e.g., reentrancy, integer overflow, key extraction, replay attack)
2. **Затронутый компонент** (e.g., NoethrionAttester.sol, ESP32 firmware, spec секция 4.2)
3. **Расположение** (file path, номера строк, commit hash)
4. **Пошаговое воспроизведение** если возможно
5. **Proof of concept** если доступно (пожалуйста, отредактируйте любые чувствительные данные)
6. **Оценка impact** — что может сделать атакующий?
7. **Предложенное исправление** если есть

### Что ожидать от нас

| Стадия | Timeline |
|---|---|
| Первичное подтверждение | В течение 48 часов |
| Triage и оценка severity | В течение 7 дней |
| Status updates | Минимум каждые 14 дней |
| Разработка патча | Зависит от severity (см. ниже) |
| Public disclosure | Согласовано с reporter |

### Timeline ответа по severity

Мы стремимся устранять уязвимости в соответствии с их severity:

- **Critical** (funds at risk, key extraction, consensus failure): патч в течение 7 дней
- **High** (DoS, значительная утечка данных): патч в течение 30 дней
- **Medium** (ограниченная exposure, требует unusual conditions): патч в течение 90 дней
- **Low** (теоретические или low-impact issues): патч в следующем release cycle

### Bug bounty программа

В настоящее время мы не предлагаем bug bounty программу. Планируем установить её в координации с платформами как Immunefi после того как наши smart contracts достигнут v1.0 и пройдут формальный аудит.

Тем временем, все валидные отчёты будут:

- Публично acknowledged (с разрешения reporter) в наших security advisories
- Перечислены в `CONTRIBUTORS.md` проекта
- Рассмотрены для retroactive recognition после запуска bug bounty программы

### Scope

Следующее **в scope** этой политики:

- ✅ Smart contracts в `contracts/src/`
- ✅ Firmware в `firmware/src/`
- ✅ Спецификация протокола в `spec/`
- ✅ Документация которая может ввести implementers в заблуждение
- ✅ CI/CD workflows которые могут скомпрометировать releases

Следующее **out of scope**:

- ❌ Third-party сервисы которые мы не контролируем (e.g., GitHub itself, Cloudflare)
- ❌ Issues требующие физического доступа который мы не authorized
- ❌ Social engineering контрибьюторов
- ❌ DoS атаки на нашу public инфраструктуру (websites)
- ❌ Issues уже public disclosed

### Coordinated disclosure

Мы следуем industry-standard coordinated disclosure:

1. Отчёт получен privately
2. Мы подтверждаем и разрабатываем fix
3. Патч deployed на затронутые системы
4. Public disclosure с attribution (максимум 90 дней с отчёта, раньше если исправлено)

Если вы считаете что уязвимость активно эксплуатируется, пожалуйста укажите это в вашем отчёте. Мы ускорим response.

### Hall of Fame

Уязвимости сообщённые ответственно будут acknowledged здесь (с разрешения reporter):

- *Пока нет отчётов — будьте первым*

### Криптографические примитивы

Протокол Noethrion полагается на следующие криптографические предположения. Если вы можете сломать любое из них, вы нашли критическую уязвимость:

- **ECDSA P-256** (secure element signing)
- **SHA-256** (Merkle tree hashing)
- **Keccak-256** (EVM-compatible hashing)
- **ATECC608B** secure element key isolation
- **Ethereum L2 security model** (EVM-compatible Layer 2, fraud proofs)

Issues с этими примитивами на алгоритмическом уровне должны сообщаться соответствующим upstream maintainers (e.g., Microchip, the relevant L2 team). Issues с нашей реализацией этих примитивов должны сообщаться нам.

---

**Thank you for helping keep Noethrion secure. / Спасибо что помогаете поддерживать безопасность Noethrion.**

η = E_useful / E_total
