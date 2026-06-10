# Noethrion Firmware — ESP32 + ATECC608B

Reference firmware for hardware-attested kWh measurement. The target design is to read a kWh meter, sign the (timestamp, energy_wh) tuple inside a tamper-resistant secure element, and publish the signed attestation upstream. The current skeleton implements only part of this — see Status below.

**Status:** Phase 5 skeleton — does not yet build out of the box; dependency packaging work is pending (see [Verification status](#verification-status) below). Probes the I²C bus + secure element handshake; meter reading and upstream publication are stubs awaiting hardware bring-up.

---

## Hardware (Bill of Materials)

| Part | Spec | Approx. cost (USD) |
|------|------|--------------------|
| ESP32 dev board | ESP32-WROOM-32 (any reputable vendor) | $8 |
| Secure element | Microchip ATECC608B (CryptoAuthentication) | $1.50 |
| I²C breakout | SOIC-8 → DIP adapter or SparkFun ATECC608A breakout | $5 |
| kWh meter input | Pulse output (S0 standard, 1000 imp/kWh) OR Modbus RTU RS-485 transceiver (MAX485) | $5 |
| Wiring | Dupont jumpers, 4.7 kΩ I²C pull-ups (×2) | $2 |
| **Total** | | **~$20-25** |

Prices reflect AliExpress / direct-source procurement. Sourcing the same BOM from US distributors (Mouser, DigiKey) lands closer to **$35-45**.

Validated meters (POC):
- Eastron SDM230-Modbus (single-phase, RS-485)
- Generic DIN-rail kWh meters with S0 pulse output

## Pinout (ESP32 → peripherals)

| ESP32 pin | Peripheral | Notes |
|-----------|------------|-------|
| GPIO 21 | ATECC608B SDA | I²C, requires 4.7 kΩ pull-up to 3.3V |
| GPIO 22 | ATECC608B SCL | I²C, requires 4.7 kΩ pull-up to 3.3V |
| 3.3V | ATECC608B VCC | |
| GND | ATECC608B GND | |
| GPIO 25 | RS-485 RO (optional, Modbus path) | |
| GPIO 26 | RS-485 DI (optional, Modbus path) | |
| GPIO 27 | RS-485 DE/RE tied (optional, Modbus path) | |
| GPIO 32 | S0 pulse input (optional, pulse path) | Pulled up internally; ISR on falling edge |

A fresh, unconfigured ATECC608B answers on I²C address `0x60` (7-bit). Pre-provisioned variants — most notably the `ATECC608B-MAHDA-T` Trust&Go family — typically ship at `0x6A` per their factory configuration; check the part-specific datasheet before assuming the default.

## Build (PlatformIO)

```bash
# Install PlatformIO Core (one-time)
pip install platformio

# Build
cd firmware
pio run

# Upload to ESP32 (auto-detects port)
pio run -t upload

# Monitor serial output (115200 baud)
pio device monitor -b 115200
```

Or use the PlatformIO IDE (VS Code extension) — open `firmware/` as workspace and use the toolbar.

## Project structure

```
firmware/
├── platformio.ini      PlatformIO build configuration
├── src/
│   └── main.cpp        Application entry point (setup + loop)
├── include/            Project-wide headers (currently empty)
├── test/               Unit tests (empty placeholder)
└── README.md           This file
```

## What the skeleton does today

1. Initializes serial output (115200 baud).
2. Lets the cryptoauthlib HAL initialise the I²C bus inside `atcab_init()` — the pin values printed in the boot banner are informational.
3. Probes for ATECC608B presence via `cryptoauthlib`.
4. On success: prints the part's serial number and config zone lock state.
5. Enters a 10-second tick loop: emits a placeholder JSON `{ts, wh, sig:"<stub>"}` line over serial.

Real meter integration, real ECDSA signing, and upstream publication are explicitly stubbed (`// TODO`) and live in the next firmware milestone. The JSON line is a placeholder only — the production token format is Canonical CBOR per [`../spec/noethrion-attestation-v0.1.md`](../spec/noethrion-attestation-v0.1.md) §4.1.

## Provisioning note

ATECC608B ships **unconfigured**. Before useful crypto, the part needs:
1. Config zone written (key slot policies, GenKey rules)
2. Config zone locked (irreversible — verify carefully)
3. Data zone locked (irreversible)
4. Per-device ECC key generated in slot 0

A provisioning helper is available at [`../tools/provision_atecc.py`](../tools/provision_atecc.py). The skeleton itself runs in **probe-only mode** against unconfigured parts.

## Security model (one-line summary)

The ATECC608B holds a per-device ECC P-256 private key that is generated on-chip and **cannot be extracted**. Every kWh attestation is signed inside the element, so a compromised host MCU can lie about *what* to sign but cannot forge signatures from a different device. Pairing (attester contract ↔ device public key) happens at provisioning.

Detailed threat model: see [`../THREAT_MODEL.md`](../THREAT_MODEL.md).

## Verification status

⚠️ **This skeleton does not yet compile out of the box.** First build attempted 2026-06-09 (PlatformIO Core 6.1.19, `espressif32@6.x`): the framework and dependencies download fine, but the pinned `cryptoauthlib` git source ships only a stub `library.json` with no PlatformIO build configuration. The library dependency finder therefore compiles the entire repository (`app/`, `test/`, …) without the `lib/` include path, and the CMake-generated `atca_config.h` is never produced — the build fails on missing headers before reaching this project's code.

Bring-up options (next firmware milestone):

1. Vendor a minimal PlatformIO port of `cryptoauthlib` — source filter restricted to `lib/`, plus a hand-written `atca_config.h` enabling the ESP32 I²C HAL; or
2. Switch `lib_deps` to a PlatformIO-packaged port of the same library (requires supply-chain review before adoption).

Once the dependency builds, remaining issues to watch:

- **`ATCAIfaceCfg` field name drift.** Field-by-field init in `setup()` uses `address`/`bus`/`baud` — these are stable in v3.7.x but rename across major versions. If build fails on these, check the relevant struct in `lib/cryptoauthlib/lib/atca_iface.h` after first dependency download.
- **HAL availability.** `cryptoauthlib` ships HAL implementations per platform; ESP32 Arduino path uses the I²C HAL via Wire. If linker can't find `hal_i2c_*` symbols, may need to enable a HAL flag in `platformio.ini` (`-DATCA_HAL_I2C` / similar).
- **`atcab_init` returning non-zero (`ATCA_NOT_INITIALIZED`)** with no part attached is expected — boards without ATECC608B will still flash and run (probe-only mode).

After the first successful build, update this section to "✅ Verified compile on \<date\>".

## Third-party library license note

The reference firmware depends on [`cryptoauthlib`](https://github.com/MicrochipTech/cryptoauthlib) under the **Microchip Software License Agreement (MSLA)**, which permits redistribution but restricts use to Microchip products:

> "you may use the Microchip Software and any derivatives **exclusively with Microchip products**"

This is acceptable for this reference firmware because the target part — ATECC608B — is a Microchip product. **Do not** copy this firmware's `platformio.ini` to a project that uses a non-Microchip secure element (Infineon OPTIGA Trust M, NXP EdgeLock SE050, etc.) and assume `cryptoauthlib` is the correct integration path. Other vendors ship their own host libraries (see [`docs/hardware-vendor-matrix.md`](../docs/hardware-vendor-matrix.md)).

The full license is reviewed in [`docs/audit/license-audit.md`](../docs/audit/license-audit.md).

## License

MIT — see repo root `LICENSE`. The MIT license applies to this firmware's own source; third-party dependencies retain their own licenses as listed in `platformio.ini` and the audit document linked above.
