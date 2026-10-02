# Vendored cryptoauthlib — what differs from upstream

Source: https://github.com/MicrochipTech/cryptoauthlib tag `v3.7.9` (commit 7f00156), directory `lib/` only.

Dropped (not needed for ESP32 + ATECC608B over I2C): `cmake/`, `pkcs11/`, `jwt/`, `mbedtls/`, `openssl/`, `wolfssl/`, `crypto/{mbedtls,openssl,wolfssl}/`, all non-ESP32 HALs (Linux, Windows, SAM/UC3/Harmony/START, kit/HID/bridge, SWI), `CMakeLists.txt`, `*.in`.

Added:
- `library.json` — PlatformIO manifest (upstream has no `build` section, so PIO could not build it from git).
- `src/atca_config.h` — hand-written from `atca_config.h.in` (CMake normally generates it): `ATCA_HAL_I2C`, `ATCA_ATECC608_SUPPORT`, `ATCA_PRINTF`, `ATCA_USE_ATCAB_FUNCTIONS`, `MAX_PACKET_SIZE 1072`, `ATCA_CHECK_PARAMS_EN 1`, `ATCACERT_{COMPCERT,FULLSTOREDCERT}_EN 1`; everything else off.

Patched:
- `src/hal/hal_esp32_i2c.c` `hal_i2c_release()` — `dev_handle` guarded by the ESP-IDF >= 5.2 check (upstream bug: member does not exist on the legacy `driver/i2c.h` path used by Arduino-ESP32 2.x).

To bump: re-copy upstream `lib/`, re-apply the three items above, re-check `ATCAIfaceCfg` field names used in `src/main.cpp`.
