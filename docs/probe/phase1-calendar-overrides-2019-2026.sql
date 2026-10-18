-- Explicit exchange-closed dates from HNX's published annual holiday notices.
-- This is partial closure evidence, not a complete open-session calendar.
-- Applied dates have no canonical bars in the current local database.
BEGIN;

WITH ranges (start_date, end_date, reason) AS (
    VALUES
        (DATE '2018-12-31', DATE '2019-01-01', 'HNX 2019 New Year closure; https://www.hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60002874.html?_page=1'),
        (DATE '2019-02-04', DATE '2019-02-08', 'HNX 2019 Lunar New Year closure; https://www.hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60002874.html?_page=1'),
        (DATE '2019-04-15', DATE '2019-04-15', 'HNX 2019 Hung Kings Day closure; https://www.hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60002874.html?_page=1'),
        (DATE '2019-04-29', DATE '2019-05-01', 'HNX 2019 Reunification and Labour Day closure; https://www.hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60002874.html?_page=1'),
        (DATE '2019-09-02', DATE '2019-09-02', 'HNX 2019 National Day closure; https://www.hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60002874.html?_page=1'),
        (DATE '2019-05-04', DATE '2019-05-04', 'HNX states no securities trading on the 2019 make-up Saturday; https://www.hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60004039.html?_page=1'),

        (DATE '2020-01-01', DATE '2020-01-01', 'HNX 2020 New Year closure; https://hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60006486.html?_page=1'),
        (DATE '2020-01-23', DATE '2020-01-29', 'HNX 2020 Lunar New Year closure; https://hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60006486.html?_page=1'),
        (DATE '2020-04-02', DATE '2020-04-02', 'HNX 2020 Hung Kings Day closure; https://hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60006486.html?_page=1'),
        (DATE '2020-04-30', DATE '2020-05-01', 'HNX 2020 Reunification and Labour Day closure; https://hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60006486.html?_page=1'),
        (DATE '2020-09-02', DATE '2020-09-02', 'HNX 2020 National Day closure; https://hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60006486.html?_page=1'),

        (DATE '2021-01-01', DATE '2021-01-01', 'HNX 2021 New Year closure; https://hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60010564.html?_page=1'),
        (DATE '2021-02-10', DATE '2021-02-16', 'HNX 2021 Lunar New Year closure; https://hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60010564.html?_page=1'),
        (DATE '2021-04-21', DATE '2021-04-21', 'HNX 2021 Hung Kings Day closure; https://hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60010564.html?_page=1'),
        (DATE '2021-04-30', DATE '2021-04-30', 'HNX 2021 Reunification Day closure; https://hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60010564.html?_page=1'),
        (DATE '2021-05-03', DATE '2021-05-03', 'HNX 2021 Labour Day observed closure; https://hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60010564.html?_page=1'),
        (DATE '2021-09-02', DATE '2021-09-03', 'HNX 2021 National Day closure; https://hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60010564.html?_page=1'),

        (DATE '2022-01-03', DATE '2022-01-03', 'HNX 2022 observed New Year closure; https://hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60013320.html?_page=1'),
        (DATE '2022-01-31', DATE '2022-02-04', 'HNX 2022 Lunar New Year closure; https://hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60013320.html?_page=1'),
        (DATE '2022-04-11', DATE '2022-04-11', 'HNX 2022 observed Hung Kings Day closure; https://hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60013320.html?_page=1'),
        (DATE '2022-05-02', DATE '2022-05-03', 'HNX 2022 Reunification and Labour Day observed closure; https://hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60013320.html?_page=1'),
        (DATE '2022-09-01', DATE '2022-09-02', 'HNX 2022 National Day closure; https://hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60013320.html?_page=1'),

        (DATE '2023-01-02', DATE '2023-01-02', 'HNX 2023 observed New Year closure; https://www.hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60015701.html?_page=1'),
        (DATE '2023-01-20', DATE '2023-01-26', 'HNX 2023 Lunar New Year closure; https://www.hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60015701.html?_page=1'),
        (DATE '2023-05-01', DATE '2023-05-03', 'HNX 2023 holiday closure; https://www.hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60015701.html?_page=1'),
        (DATE '2023-09-01', DATE '2023-09-01', 'HNX 2023 National Day closure; https://www.hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60015701.html?_page=1'),
        (DATE '2023-09-04', DATE '2023-09-04', 'HNX 2023 observed National Day closure; https://www.hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60015701.html?_page=1'),

        (DATE '2024-01-01', DATE '2024-01-01', 'HNX 2024 New Year closure; https://www.hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60017878.html?_page=1'),
        (DATE '2024-02-08', DATE '2024-02-14', 'HNX 2024 Lunar New Year closure; https://www.hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60017878.html?_page=1'),
        (DATE '2024-04-18', DATE '2024-04-18', 'HNX 2024 Hung Kings Day closure; https://www.hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60017878.html?_page=1'),
        (DATE '2024-04-30', DATE '2024-05-01', 'HNX 2024 Reunification and Labour Day closure; https://www.hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60017878.html?_page=1'),
        (DATE '2024-09-02', DATE '2024-09-03', 'HNX 2024 National Day closure; https://www.hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60017878.html?_page=1'),

        (DATE '2025-01-01', DATE '2025-01-01', 'HNX 2025 New Year closure; https://qtcb.hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60020153.html?_page=1'),
        (DATE '2025-01-27', DATE '2025-01-31', 'HNX 2025 Lunar New Year closure; https://qtcb.hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60020153.html?_page=1'),
        (DATE '2025-04-07', DATE '2025-04-07', 'HNX 2025 Hung Kings Day closure; https://qtcb.hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60020153.html?_page=1'),
        (DATE '2025-04-30', DATE '2025-05-02', 'HNX 2025 Reunification and Labour Day closure; https://qtcb.hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60020153.html?_page=1'),
        (DATE '2025-09-01', DATE '2025-09-02', 'HNX 2025 National Day closure; https://qtcb.hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60020153.html?_page=1'),
        (DATE '2025-04-26', DATE '2025-04-26', 'HNX states no securities trading on the 2025 make-up Saturday; https://qtcb.hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60020153.html?_page=1'),

        (DATE '2026-01-01', DATE '2026-01-02', 'HNX adjusted New Year closure; https://www.hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60022084.html?_page=1'),
        (DATE '2026-02-16', DATE '2026-02-20', 'HNX 2026 Lunar New Year closure; https://portal.hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60021971.html?_page=1'),
        (DATE '2026-04-27', DATE '2026-04-27', 'HNX 2026 Hung Kings Day closure; https://portal.hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60021971.html?_page=1'),
        (DATE '2026-04-30', DATE '2026-05-01', 'HNX 2026 Reunification and Labour Day closure; https://portal.hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60021971.html?_page=1'),
        (DATE '2026-08-31', DATE '2026-09-02', 'HNX 2026 National Day closure; https://portal.hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60021971.html?_page=1'),
        (DATE '2026-01-10', DATE '2026-01-10', 'HNX states no securities trading on the 2026 New Year make-up Saturday; https://www.hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60022084.html?_page=1'),
        (DATE '2026-08-22', DATE '2026-08-22', 'HNX states no securities trading on the 2026 National Day make-up Saturday; https://portal.hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60021971.html?_page=1')
), expanded AS (
    SELECT DISTINCT generate_series(start_date, end_date, interval '1 day')::date AS trade_date,
           reason
    FROM ranges
)
INSERT INTO core.calendar_overrides (trade_date, is_session, reason)
SELECT trade_date, false, reason
FROM expanded
ON CONFLICT (trade_date) DO NOTHING;

COMMIT;
