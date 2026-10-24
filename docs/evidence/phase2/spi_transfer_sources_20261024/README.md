# SPI HNX to UPCoM transfer source packet

Captured 2026-10-24. Exact per-file UTC capture timestamps, source URLs, byte sizes, SHA-256 values, each document's separate claims, and document-specific limitations are recorded in `manifest.csv`. `prepare_import.ps1` verifies these values against the archived files and generates `landing_stage.csv` plus `import_landings_reportclone.sql`; it does not connect to or write to a database. The generated SQL has an exact disposable report-clone database guard and repeats the embedded identity/metadata checks. It has not been executed.

| File | Source URL | Bytes | SHA-256 | What it establishes |
|---|---|---:|---|---|
| spi_hnx_delisting_notice_2642_2025-06-13.pdf | https://owa.hnx.vn/ftp///cims/2025/6_W3/000000015061781_2642tb_0001.pdf | 479081 | DC07F82346ABB7F3EA36F4B1E90FAE5358EE2E4D7690BF9FE4EC13A6C4A7C96F | Official signed HNX Notice 2642/TB-SGDHN, dated 2025-06-13, identifies SPI. It states delisting effective 2025-07-10 and final HNX trading day 2025-07-09, and gives the mandatory delisting reason. The scanned page was visually reviewed. |
| spi_vsdc_hnx_upcom_transfer_2025-06-19.html | https://vsdc.vn/vi/ad1/184158 | 71701 | 543F8F808E2A01857F797776F98A3D8ED1B2D913A8CBD54F482F18921466401B | Official VSDC notice published 2025-06-19 says SPI data transfer is from listed HNX to UPCoM effective 2025-07-14; it cites HNX Decision 733/QĐ-SGDHN dated 2025-06-13. This establishes the venue transition process, but not a first trading date. |
| spi_hnx_upcom_profile.html | https://hnx.vn/vi-vn/cophieu-etfs/chi-tiet-chung-khoan-uc-spi.html | 253951 | E9B26570F76CFFE3A2586B5909EACE430E3B4C09C522FD756FFE668049A617AE | Official HNX profile identifies SPI / CTCP Spiral Galaxy, UPCoM, and first trading date 2025-07-25. Profile captured in 2026, so treat it as current profile evidence retrieved at capture time. |

## Interval conclusion

The assessed SPI interval 2025-07-09 to 2025-07-25 is supported as a venue transfer: the HNX notice gives the final HNX trade on 2025-07-09; the HNX profile gives the first UPCoM trade on 2025-07-25; VSDC independently documents transfer from HNX to UPCoM. Together, these sources explain the gap endpoints as a venue transition. They do not prove SPI was suspended or establish whether it had trades on individual sessions in the interval. No gap assessment or database was modified.

## Verified archive import
Root imported the three checked source landings into the isolated report clone: first pass inserted3, repeat inserted0; both transactions and byte/metadata identity checks passed. See import_first_20261024.log and import_repeat_20261024.log. No lifecycle event, bar or eligibility record was changed.
