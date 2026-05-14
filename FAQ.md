# Frequently asked questions

Thirty answers to the questions we expect to receive most often. Written for engineers, researchers, regulators, and the curious; not for traders. If your question is not here, the project repository's Discussions section is the best place to ask.

---

## Positioning

### 1. What is Noethrion, in one sentence?
An open standard for hardware-attested verification of electricity generation — one kilowatt-hour, signed at the meter by a tamper-resistant secure element, anchored on a public ledger so anyone can verify it without trusting an intermediary.

### 2. Is this a cryptocurrency?
No. NOET is a unit of accounting inside the protocol, representing one verified kilowatt-hour. It is not a payment instrument, not a store of value, and not intended to compete with sovereign currencies. The closest analogy is a transferable digital certificate, not a token in the speculative-asset sense.

### 3. Will NOET have a market price?
We do not project, target, or coordinate price. Like Certificate Authority signatures or domain names, the unit has utility because relying parties accept it as evidence of a specific real-world event. Whether and where it trades is a market question; the protocol's economics are designed so that the **Foundation captures none of the price upside** even if it exists.

### 4. Is there a token sale, ICO, presale, or private allocation round?
No. There has been no token sale, there is no token sale planned, and the Foundation's governing documents make conducting one materially difficult by design. We are publishing a specification and an invitation, not selling anything.

### 5. Are you raising venture funding?
Not at this stage. The protocol is built by a small team operating on minimal cost basis, with funding planned to come from public-goods grants (Gitcoin, Ethereum Foundation ESP, equivalents) and the Foundation's bootstrap treasury allocation. If we accept private capital at any point, the terms will be public and structured to preserve Foundation independence.

### 6. What is the business model?
The Foundation has no business model in the for-profit sense. Hardware vendors who integrate the standard, certifying authorities who audit them, and integrators who build downstream products are expected to capture economic value. The Foundation's role is to administer the standard, run a small reference implementation, and resolve disputes — funded by treasury, grants, and member dues, not by selling services.

### 7. Who owns Noethrion?
No one. The protocol specification is licensed permissively (MIT / Apache 2.0). The Foundation — once incorporated as a Swiss Stiftung — will administer the standards process, but will not own the protocol in the corporate sense. The closest organizational analogies are the Linux Foundation, the IETF, the Bluetooth SIG, and ICANN.

### 8. How is this different from earlier blockchain-energy projects?
Earlier attempts in the 2017–2021 era largely focused on peer-to-peer energy trading, which runs into hard physical constraints (the grid is not a market in the trading-floor sense) and regulatory ones. Noethrion does not attempt trading. It attempts only the narrower problem of **verifying that a kilowatt-hour was generated where and when it was claimed** — and stops there. The downstream economic uses are left to integrators.

---

## Technical

### 9. Why hardware attestation, instead of zero-knowledge proofs or software oracles?
Hardware turns the verification problem into a physics problem. To forge an attestation, an adversary must either physically tamper with the meter (detectable through existing revenue-grade sealing procedures) or extract a private key from a CC EAL5+ secure element (currently infeasible against state-of-the-art parts). Software-only schemes leave residual trust assumptions that are difficult to make legally meaningful.

### 10. Why ECDSA P-256, and not Ed25519 or secp256k1?
P-256 is the curve natively supported by widely available low-cost secure elements suitable for meter integration. Performance is sufficient for the per-minute signing cadence. NIST-curve acceptance among corporate cryptographic policies is also pragmatically broader than Ed25519. A formal Architecture Decision Record is in `docs/adr/`.

### 11. What about post-quantum security?
P-256 is not post-quantum secure, and we say so plainly. A migration path to ML-DSA (CRYSTALS-Dilithium, once finalized in FIPS 204) is described in Section 5.2 of the Internet-Draft. The token format reserves room for an algorithm identifier and a versioned key identifier so historical attestations remain verifiable across the rotation.

### 12. Why a Layer 2 rollup and not Ethereum mainnet?
Gas economics. At a million attestations per day, mainnet would be prohibitively expensive while contributing nothing security-wise that an EVM-compatible Layer 2 does not already provide for this use case. The specific settlement layer is deliberately not locked into the spec yet; the Foundation will publish a Layer 2 selection criteria document and a formal selection at a later spec version.

### 13. Why not your own Layer 1 chain?
Past attempts to build energy-specific Layer 1s have a poor track record. Building, securing, and validator-bootstrapping a new chain is roughly two years of full-time work that contributes nothing to the protocol's core problem. We use an existing EVM-compatible rollup so the Foundation can focus on the verification primitive.

### 14. What stops a device operator from lying about the kilowatt-hours they generate?
The meter signs the tuple `(kWh, timestamp, deviceID)` inside the secure element, which generated its private key on-die. The device operator can either: (a) report less than they generate (no economic incentive to do so), or (b) physically tamper with the meter (detectable through existing sealing audits). Forging signatures from the device's public key without the private key is the underlying cryptographic problem.

### 15. What if the secure element itself gets compromised?
The Endorser responsible for that device batch revokes the endorsement; the on-chain registry updates; relying parties stop accepting attestations from devices in the affected batch. The protocol's per-device hash chain (`prev` claim) ensures that historical attestations remain verifiable against the pre-compromise endorsement, limiting blast radius.

### 16. How does this scale to billions of attestations?
Batching. Off-chain aggregation collects up to 65,536 attestations per Merkle tree, anchored as a single on-chain commitment. Verification of any individual attestation is a logarithmic Merkle proof check, not a linear scan of all leaves. The system is designed so verification cost grows logarithmically with the size of the set being verified against.

### 17. What is the gas cost per attestation?
Per individual attestation: zero — only the Merkle root commits on-chain. The amortized cost is the gas of one `proposeBatch()` call plus `(threshold - 1)` `voteBatch()` calls plus one `finalizeBatch()` call, divided across the number of leaves in the batch. At 65,536 leaves per batch, threshold around 3–5, and current Layer 2 gas economics this still lands well under a fraction of a cent per attestation; the exact number depends on the chosen settlement layer and quorum size.

### 18. Can this be ported to non-EVM chains?
The signature scheme and CBOR token format are chain-agnostic. The on-chain commitment component is EVM-specific in the current reference implementation, but a port to other smart-contract platforms is a straightforward exercise. The Foundation will likely maintain multiple reference implementations once the standard stabilizes.

---

## Market

### 19. How does this compare to RECs, Guarantees of Origin, and I-RECs?
RECs / GoOs / I-RECs are annual, aggregate, brokered instruments. Noethrion provides device-level, hourly, cryptographically verifiable attestation. The two are not in direct conflict — existing certificate schemes can extend their registries to incorporate Noethrion-attested generation as the primitive evidence layer. That integration work is on the protocol roadmap.

### 20. What is the relationship to CBAM?
The EU Carbon Border Adjustment Mechanism took effect on 1 January 2026, requiring importers to demonstrate embedded carbon content at the source. There is currently no globally interoperable infrastructure for verifiable energy provenance that satisfies this requirement at scale. Noethrion does not implement CBAM compliance directly; it provides the underlying primitive that CBAM-aligned attestation services can build on.

### 21. Why now? Why didn't this exist before?
Three things converged in 2024–2026: (a) hyperscalers signed multi-gigawatt nuclear PPAs requiring 24/7 hourly matching, breaking the annual-aggregate model; (b) EU CBAM came into force; (c) cheap, mass-produced CC EAL5+ secure elements made hardware-rooted attestation economically viable at meter scale. The technical components existed before; the demand for their combination did not.

### 22. What is the addressable market?
We consciously do not publish a market sizing. The honest answer is that any infrastructure standard's "market" is bounded by where the standard goes, not by an a-priori spreadsheet. For comparable historical reference, the Linux Foundation administers a kernel that underpins economic activity in the trillions; we expect the Foundation itself to operate on a budget of low hundreds of millions of dollars over a multi-decade horizon.

### 23. Who is the customer?
The protocol has no customer. The hardware vendors who ship Noethrion-attested devices, the integrators who consume the attestations in downstream products, and the relying parties (compliance officers, sustainability auditors, regulators) who rely on the verification are the ecosystem. The Foundation serves all three but sells to none.

---

## Concerns

### 24. What about privacy of energy consumers?
A continuous public record of per-device generation creates real privacy risks for small-scale producers (residential rooftop solar in particular). The specification documents this directly in Section 9 (Privacy Considerations) and provides mitigations: timestamp rounding, batch padding, and an optional zero-knowledge attestation variant planned for v0.2. Participation is voluntary; the protocol does not coerce disclosure.

### 25. What about smart-meter manufacturers — will they cooperate?
The protocol is designed to be vendor-neutral and integration-light. A device manufacturer adds approximately a few kilobytes of firmware to integrate Noethrion attestation; the secure element costs roughly a dollar at volume. Several manufacturers have indicated interest in the abstract. The Foundation does not pick vendors; it certifies them through an open process to be specified in v0.2.

### 26. What jurisdictions does this work in?
The protocol itself is jurisdiction-neutral; it is an open mathematical specification. The Foundation will incorporate in Switzerland as a Stiftung — a non-profit legal structure well-suited for administering global standards. Specific implementations (hardware certification, registry operation, dispute resolution) may require local regulatory engagement; this is operational policy, not protocol design.

### 27. Is the protocol patent-encumbered?
The specification is published under permissive open-source licenses (MIT / Apache 2.0). The Foundation's bylaws require members to grant royalty-free patent licenses for techniques they contribute to the standard. We expect to publish a formal Patent Policy at the IETF Internet-Draft stage. No known patent risk currently encumbers the v0.1 protocol.

---

## Engagement

### 28. How can I contribute?
Open a GitHub Discussion or a Pull Request. The hardest open problems right now are (a) the post-quantum migration plan, (b) the Endorser registry governance model, and (c) on-chain fraud-proof verification feeding automatic slashing (v0.3+ work). The m-of-n threshold validator quorum is shipped in v0.2 (ADR-006). Critical reviewers — engineers who think the design is wrong — are especially valued.

### 29. Are you hiring?
Not in the conventional employment sense at this stage. The protocol is built by a small team and an expanding circle of voluntary contributors. Once the Foundation incorporates we expect to bring on a small full-time core (specification editor, security engineer, governance coordinator) funded by grant and treasury allocation — not VC capital. Watch the repository for openings.

### 30. Are you funded?
The project currently operates on minimal cost basis from a small founding contribution. Grant applications to public-goods funding rounds are in progress. The Foundation's bootstrap treasury (5% of the total NOET supply, vested over four years) is fixed at protocol genesis and intended to fund operations for the multi-decade horizon. We are deliberately not raising venture capital at this stage.

---

*If your question is not here, please open a [Discussion](https://github.com/noethrion/noethrion/discussions) on the repository or email `team@noethrion.com`. We update this file as questions recur.*

*η = E_useful / E_total*

---

## 🇷🇺 FAQ на русском

Тридцать ответов на вопросы, которые мы ожидаем чаще всего. Написаны для инженеров, исследователей, регуляторов, и любопытных — не для трейдеров. Если твоего вопроса здесь нет, лучшее место спросить — Discussions репозитория.

### Позиционирование

**1. Что такое Noethrion одним предложением?**
Открытый стандарт аппаратно-подтверждённой верификации генерации электроэнергии — один киловатт-час, подписанный на счётчике tamper-resistant secure element'ом, заанкоренный на public ledger так, что любой может верифицировать без доверия посреднику.

**2. Это криптовалюта?**
Нет. NOET — единица учёта внутри протокола, представляющая один верифицированный киловатт-час. Это не платёжный инструмент, не store of value, и не предназначен конкурировать с суверенными валютами. Ближайшая аналогия — переносимый цифровой сертификат, не token в спекулятивном смысле.

**3. Будет ли у NOET рыночная цена?**
Мы не проектируем, не таргетируем, и не координируем цену. Как подписи Certificate Authority или доменные имена, unit имеет utility потому что relying parties принимают его как evidence конкретного real-world события. Будет ли он торговаться — рыночный вопрос; экономика протокола спроектирована так, что **Foundation не получает price upside** даже если он существует.

**4. Будет ли token sale, ICO, presale, или приватное размещение?**
Нет. Token sale не было, не планируется, и governing documents Foundation делают его материально трудным by design. Мы публикуем спецификацию и приглашение, не продаём ничего.

**5. Привлекаете ли венчурное финансирование?**
Не на этом этапе. Протокол строит небольшая команда на минимальной cost basis, с funding планируемым через public-goods гранты (Gitcoin, Ethereum Foundation ESP, эквиваленты) и bootstrap treasury allocation Foundation. Если когда-либо примем private capital — условия будут публичными и структурированы для сохранения Foundation independence.

**6. Какая бизнес-модель?**
У Foundation нет бизнес-модели в for-profit смысле. Hardware vendors интегрирующие стандарт, certifying authorities аудитящие их, и integrators строящие downstream продукты ожидаемо capture экономическую value. Роль Foundation — администрировать стандарт, запускать small reference implementation, resolve disputes — финансируется treasury, грантами и member dues, не продажей сервисов.

**7. Кто owns Noethrion?**
Никто. Спецификация протокола licensed permissively (MIT / Apache 2.0). Foundation — после incorporation как Swiss Stiftung — будет администрировать standards process, но не will owns протокол в corporate смысле. Ближайшие организационные аналогии: Linux Foundation, IETF, Bluetooth SIG, ICANN.

**8. Чем это отличается от ранних blockchain-energy проектов?**
Ранние попытки эры 2017-2021 в основном фокусировались на peer-to-peer energy trading, что упирается в hard physical constraints (сеть не работает как market) и регуляторные ограничения. Noethrion не пытается trading. Он пытается решить только narrower проблему — **верифицировать что киловатт-час был сгенерирован где и когда заявлено** — и останавливается. Downstream экономические uses оставлены integrator'ам.

---

### Технические

**9. Почему hardware attestation, а не zero-knowledge proofs или software oracles?**
Hardware превращает verification problem в physics problem. Чтобы подделать аттестацию, противник должен либо физически tampered счётчик (detectable через существующие revenue-grade sealing процедуры), либо извлечь private key из CC EAL5+ secure element (сейчас infeasible против state-of-the-art parts). Software-only схемы оставляют residual trust assumptions, которые трудно сделать legally meaningful.

**10. Почему ECDSA P-256, а не Ed25519 или secp256k1?**
P-256 — кривая, которую natively поддерживают широко доступные low-cost secure elements подходящие для meter integration. Performance достаточен для per-minute signing cadence. NIST-curve acceptance среди корпоративных cryptographic policies pragmatically шире чем Ed25519. Формальный ADR — в `docs/adr/`.

**11. Что насчёт post-quantum безопасности?**
P-256 не post-quantum secure, и мы говорим это прямо. Migration path к ML-DSA (CRYSTALS-Dilithium, после финализации в FIPS 204) описан в Section 5.2 Internet-Draft. Token формат reserves место для algorithm identifier и versioned key identifier чтобы исторические аттестации оставались верифицируемыми через ротацию.

**12. Почему Layer 2 rollup, а не Ethereum mainnet?**
Экономика газа. На миллион аттестаций в день mainnet был бы prohibitively дорогим, не давая security что EVM-compatible Layer 2 уже не обеспечивает для этого use case. Конкретный rollup deliberately не зафиксирован в spec пока; Foundation опубликует Layer 2 selection criteria и формальный выбор в будущей версии spec.

**13. Почему не свой Layer 1?**
Предыдущие попытки построить energy-specific L1 имеют плохой track record. Построить, secure, и validator-bootstrapped новую chain — это roughly два года full-time работы которая ничего не добавляет к core problem протокола. Мы используем существующий EVM-compatible rollup чтобы Foundation могла фокусироваться на verification primitive.

**14. Что не даёт оператору устройства лгать про кВт·ч?**
Счётчик подписывает кортеж `(кВт·ч, timestamp, deviceID)` внутри secure element, который генерировал свой private key on-die. Оператор может либо: (а) сообщать меньше чем генерирует (нет экономического incentive), либо (б) физически tampered счётчик (detectable через sealing audits). Подделка подписей от публичного ключа устройства без private key — underlying cryptographic problem.

**15. Что если сам secure element скомпрометирован?**
Endorser ответственный за этот device batch revokes endorsement; on-chain registry обновляется; relying parties перестают принимать аттестации от устройств в affected batch. Per-device hash chain протокола (`prev` claim) обеспечивает что исторические аттестации остаются verifiable против pre-compromise endorsement, ограничивая blast radius.

**16. Как это масштабируется на миллиарды аттестаций?**
Batching. Off-chain aggregation собирает до 65,536 аттестаций в одном Merkle дереве, anchored как single on-chain commitment. Верификация любой отдельной аттестации — logarithmic Merkle proof check, не linear scan всех leaves. Система спроектирована так что verification cost растёт логарифмически с размером verified set.

**17. Какова стоимость газа per attestation?**
Per individual attestation: ноль — только Merkle root committed on-chain. Амортизированная стоимость — газ одного `proposeBatch()` + `(threshold - 1)` `voteBatch()` + одного `finalizeBatch()` calls, делённый на количество leaves в batch. На 65,536 leaves per batch, threshold ~3–5, и текущей Layer 2 газовой экономике — well under fraction of cent per attestation; точное число зависит от выбранного settlement layer и quorum size.

**18. Можно ли портировать на non-EVM chains?**
Signature scheme и CBOR token формат — chain-agnostic. On-chain commitment компонент — EVM-specific в текущей reference implementation, но порт на другие smart-contract платформы — прямолинейное упражнение. Foundation вероятно поддержит multiple reference implementations после стабилизации стандарта.

---

### Рынок

**19. Как это сравнивается с RECs, Guarantees of Origin, I-RECs?**
RECs / GoOs / I-RECs — annual, aggregate, brokered инструменты. Noethrion обеспечивает device-level, hourly, криптографически verifiable аттестацию. Не находятся в прямом conflict — существующие certificate schemes могут расширить свои registries чтобы включить Noethrion-attested generation как primitive evidence layer. Эта integration work — на roadmap.

**20. Каково отношение к CBAM?**
EU Carbon Border Adjustment Mechanism вступил в силу 1 января 2026, требует от importers демонстрировать embedded carbon content у источника. Глобально interoperable инфраструктура для verifiable energy provenance, удовлетворяющая этому требованию at scale, сейчас не существует. Noethrion не реализует CBAM compliance напрямую; он обеспечивает underlying primitive, на котором CBAM-aligned attestation services могут строить.

**21. Почему сейчас? Почему этого не существовало раньше?**
Три вещи converged в 2024-2026: (a) hyperscalers подписали multi-gigawatt ядерные PPAs требующие 24/7 hourly matching, ломая annual-aggregate model; (b) EU CBAM вступил в силу; (c) дешёвые, mass-produced CC EAL5+ secure elements сделали hardware-rooted attestation economically viable на meter scale. Технические components существовали раньше; demand на их комбинацию — нет.

**22. Какой addressable market?**
Сознательно не публикуем market sizing. Честный ответ: "market" любого infrastructure стандарта определяется тем куда стандарт идёт, не a-priori spreadsheet'ом. Для сравнения: Linux Foundation администрирует kernel underpinning экономическую активность в trillions; мы ожидаем что Foundation сама будет operating на low hundreds of millions of dollars budget over multi-decade horizon.

**23. Кто customer?**
У протокола нет customer. Hardware vendors отгружающие Noethrion-attested устройства, integrators consuming аттестации в downstream продуктах, и relying parties (compliance officers, sustainability auditors, регуляторы) полагающиеся на верификацию — ecosystem. Foundation обслуживает всех трёх, но не продаёт никому.

---

### Concerns

**24. Что с privacy потребителей энергии?**
Continuous public record per-device generation создаёт real privacy risks для small-scale producers (residential rooftop solar в particular). Спецификация документирует это напрямую в Section 9 (Privacy Considerations) и предоставляет mitigations: timestamp rounding, batch padding, и опциональную zero-knowledge attestation variant запланированную на v0.2. Participation добровольная; протокол не coerce disclosure.

**25. Что насчёт smart-meter производителей — кооперируют ли они?**
Протокол спроектирован vendor-neutral и integration-light. Vendor добавляет примерно несколько килобайт firmware для интеграции Noethrion attestation; secure element стоит около доллара at volume. Несколько производителей выразили interest в абстракте. Foundation не выбирает vendors; она certify их через open process, который будет specified в v0.2.

**26. В каких юрисдикциях это работает?**
Сам протокол jurisdiction-neutral; это open mathematical specification. Foundation incorporated в Switzerland как Stiftung — non-profit legal structure хорошо подходящая для администрирования global standards. Конкретные implementations (hardware certification, registry operation, dispute resolution) могут требовать local regulatory engagement; это operational policy, не protocol design.

**27. Есть ли patent encumbrance?**
Спецификация публикуется под permissive open-source лицензиями (MIT / Apache 2.0). Bylaws Foundation требуют от членов royalty-free patent licenses для techniques которые они contribute. Мы ожидаем опубликовать формальную Patent Policy на IETF Internet-Draft стадии. Известных patent рисков, encumbering v0.1 протокол, нет.

---

### Engagement

**28. Как я могу contribute?**
Открой GitHub Discussion или Pull Request. Самые трудные open problems сейчас — (a) post-quantum migration plan, (b) Endorser registry governance model, и (c) on-chain fraud-proof verification feeding automatic slashing (v0.3+ work). M-of-n threshold validator quorum уже shipped в v0.2 (ADR-006). Критические ревьюеры — инженеры считающие что дизайн неправильный — особенно ценны.

**29. Нанимаете?**
Не в conventional employment смысле на этом этапе. Протокол строит небольшая команда и расширяющийся круг добровольных contributors. После incorporation Foundation мы ожидаем привлечь небольшой full-time core (specification editor, security engineer, governance coordinator), финансируемый через грант и treasury allocation — не VC capital. Watch репозиторий для openings.

**30. Funded?**
Проект сейчас operates на минимальной cost basis от small founding contribution. Grant applications к public-goods funding rounds — в процессе. Bootstrap treasury Foundation (5% от total NOET supply, vested over four years) зафиксирован at protocol genesis и intended финансировать operations на multi-decade horizon. Мы deliberately не привлекаем VC на этом этапе.

---

*Если твоего вопроса нет — открой [Discussion](https://github.com/noethrion/noethrion/discussions) или email на `team@noethrion.com`. Файл обновляем по мере того как вопросы повторяются.*

*η = E_useful / E_total*
