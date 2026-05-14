// Noethrion firmware — ESP32 + ATECC608B reference skeleton.
// Probes the secure element on boot, then emits a placeholder attestation
// payload over serial every TICK_INTERVAL_MS. Real meter reading, ECDSA
// signing, and upstream publication are stubbed for the next milestone.

#include <Arduino.h>
#include <Wire.h>
#include <ArduinoJson.h>

// Microchip CryptoAuthentication library — provides ATCAIfaceCfg, atcab_init, etc.
// Headers already wrap declarations in `extern "C"` themselves; no manual wrapper needed.
#include "cryptoauthlib.h"

namespace {

constexpr uint32_t TICK_INTERVAL_MS = 10'000;

// Default ATECC608B I²C address (8-bit form, library convention).
// 0x60 (7-bit) << 1 = 0xC0. Some pre-provisioned parts ship at 0x6A → 0xD4.
constexpr uint8_t ATECC_I2C_ADDR_8BIT = 0xC0;

ATCAIfaceCfg atecc_cfg;  // populated in setup() — field-by-field for portability
                         // across cryptoauthlib minor versions

bool g_atecc_present = false;
uint8_t g_atecc_serial[9] = {0};

void log_banner() {
    Serial.println();
    Serial.println(F("===== Noethrion firmware ====="));
    Serial.print(F("version : "));
    Serial.println(NOETHRION_FIRMWARE_VERSION);
    Serial.print(F("chip    : ESP32, "));
    Serial.print(ESP.getChipCores());
    Serial.print(F(" cores @ "));
    Serial.print(ESP.getCpuFreqMHz());
    Serial.println(F(" MHz"));
    Serial.print(F("i2c sda : GPIO"));
    Serial.println(ATECC_I2C_SDA);
    Serial.print(F("i2c scl : GPIO"));
    Serial.println(ATECC_I2C_SCL);
    Serial.println();
}

bool init_secure_element() {
    Serial.print(F("[atecc] init ... "));

    ATCA_STATUS status = atcab_init(&atecc_cfg);
    if (status != ATCA_SUCCESS) {
        Serial.print(F("FAIL ("));
        Serial.print(status, HEX);
        Serial.println(F(")"));
        return false;
    }

    status = atcab_read_serial_number(g_atecc_serial);
    if (status != ATCA_SUCCESS) {
        Serial.print(F("serial read FAIL ("));
        Serial.print(status, HEX);
        Serial.println(F(")"));
        return false;
    }

    Serial.print(F("OK, serial="));
    for (uint8_t i = 0; i < sizeof(g_atecc_serial); ++i) {
        if (g_atecc_serial[i] < 0x10) Serial.print('0');
        Serial.print(g_atecc_serial[i], HEX);
    }
    Serial.println();

    bool config_locked = false;
    bool data_locked   = false;
    ATCA_STATUS cl_status = atcab_is_locked(LOCK_ZONE_CONFIG, &config_locked);
    ATCA_STATUS dl_status = atcab_is_locked(LOCK_ZONE_DATA,   &data_locked);
    Serial.print(F("[atecc] zone lock state: config="));
    if (cl_status != ATCA_SUCCESS) {
        Serial.print(F("unknown"));
    } else {
        Serial.print(config_locked ? F("locked") : F("UNLOCKED"));
    }
    Serial.print(F(" data="));
    if (dl_status != ATCA_SUCCESS) {
        Serial.println(F("unknown"));
    } else {
        Serial.println(data_locked ? F("locked") : F("UNLOCKED"));
    }

    if (!config_locked || !data_locked) {
        Serial.println(F("[atecc] WARN: part is not provisioned — running in probe-only mode."));
        Serial.println(F("[atecc]       use tools/provision_atecc.py before production deployment."));
    }

    return true;
}

uint64_t read_meter_wh_stub() {
    // TODO: replace with real meter integration (Modbus RTU or S0 pulse counter).
    static uint64_t fake_total_wh = 1'000'000;
    fake_total_wh += 250; // pretend 250 Wh elapsed each tick
    return fake_total_wh;
}

void emit_attestation_stub(uint64_t total_wh) {
    JsonDocument doc;  // ArduinoJson v7 — heap-allocated, no fixed capacity needed
    doc["ts"]   = (uint32_t)(millis() / 1000);
    doc["wh"]   = total_wh;
    doc["sig"]  = "<stub-not-yet-signed>";
    doc["dev"]  = g_atecc_present ? "atecc608b" : "no-secure-element";

    char out[256];
    size_t n = serializeJson(doc, out, sizeof(out));
    Serial.write(reinterpret_cast<const uint8_t*>(out), n);
    Serial.println();
}

} // namespace

void setup() {
    Serial.begin(115200);
    delay(200);
    log_banner();

    // NOTE: do NOT call Wire.begin() here — cryptoauthlib's ESP32 HAL owns
    // the I2C bus and reinitialises it inside atcab_init(). Calling Wire.begin()
    // first risks the HAL silently overriding our baud rate.

    // Field-by-field init — verbose but resilient to upstream struct changes.
    atecc_cfg.iface_type        = ATCA_I2C_IFACE;
    atecc_cfg.devtype           = ATECC608;
    atecc_cfg.atcai2c.address   = ATECC_I2C_ADDR_8BIT;
    atecc_cfg.atcai2c.bus       = 0;
    atecc_cfg.atcai2c.baud      = ATECC_I2C_FREQ;
    atecc_cfg.wake_delay        = 1500;
    atecc_cfg.rx_retries        = 20;

    g_atecc_present = init_secure_element();
}

void loop() {
    static uint32_t next_tick = 0;
    const uint32_t now = millis();

    if (now >= next_tick) {
        next_tick = now + TICK_INTERVAL_MS;
        emit_attestation_stub(read_meter_wh_stub());
    }
}
