-- Derive the expected Vietnam securities market session calendar from HNX's
-- published weekday rule and annual trading-holiday notices. This is scoped
-- to the current VCI backfill window, not a generic weekday-only calendar.
--
-- Sources:
--   HNX Guide to Trading Stocks (Monday-Friday except public holidays):
--   https://owa.hnx.vn/ftp/PORTALNEW/PUBLICFACTBOOK_FA/20190911/HNX%20Guide%20to%20trading%20stocks.pdf
--   Annual holiday notices and later exchange adjustments are linked on each
--   date below. Closures override sessions. Weekend makeup workdays remain
--   non-trading dates when the exchange says so.

BEGIN;

CREATE TEMP TABLE phase1_hnx_closed_days (
    trade_date date PRIMARY KEY,
    reason text NOT NULL
) ON COMMIT DROP;

WITH ranges (start_date, end_date, reason) AS (
    VALUES
        (DATE '2018-12-31', DATE '2019-01-01', 'HNX 2019 New Year closure; https://www.hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60002874.html?_page=1'),
        (DATE '2019-02-04', DATE '2019-02-08', 'HNX 2019 Lunar New Year closure; https://www.hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60002874.html?_page=1'),
        (DATE '2019-04-15', DATE '2019-04-15', 'HNX 2019 Hung Kings Day closure; https://www.hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60002874.html?_page=1'),
        (DATE '2019-04-29', DATE '2019-05-01', 'HNX 2019 Reunification and Labour Day closure; https://www.hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60002874.html?_page=1'),
        (DATE '2019-09-02', DATE '2019-09-02', 'HNX 2019 National Day closure; https://www.hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60002874.html?_page=1'),
        (DATE '2019-05-04', DATE '2019-05-04', 'HNX states no securities trading on the 2019 makeup Saturday; https://www.hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60004039.html?_page=1'),

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
        (DATE '2022-05-02', DATE '2022-05-03', 'HNX 2022 observed Reunification and Labour Day closure; https://hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60013320.html?_page=1'),
        (DATE '2022-09-01', DATE '2022-09-02', 'HNX 2022 National Day closure; https://hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60013320.html?_page=1'),

        (DATE '2023-01-02', DATE '2023-01-02', 'HNX 2023 observed New Year closure; https://www.hnx.vn/vi-vn/m-tin-tuc-hnx/Thong%20bao%20ve%20viec%20cong%20bo%20lich%20nghi%20giao%20dich%20trong%20nam%202023-60015701-1.html'),
        (DATE '2023-01-20', DATE '2023-01-26', 'HNX 2023 Lunar New Year closure; https://www.hnx.vn/vi-vn/m-tin-tuc-hnx/Thong%20bao%20ve%20viec%20cong%20bo%20lich%20nghi%20giao%20dich%20trong%20nam%202023-60015701-1.html'),
        (DATE '2023-05-01', DATE '2023-05-03', 'HNX 2023 holiday closure including observed Hung Kings Day; https://www.hnx.vn/vi-vn/m-tin-tuc-hnx/Thong%20bao%20ve%20viec%20cong%20bo%20lich%20nghi%20giao%20dich%20trong%20nam%202023-60015701-1.html'),
        (DATE '2023-09-01', DATE '2023-09-01', 'HNX 2023 National Day closure; https://www.hnx.vn/vi-vn/m-tin-tuc-hnx/Thong%20bao%20ve%20viec%20cong%20bo%20lich%20nghi%20giao%20dich%20trong%20nam%202023-60015701-1.html'),
        (DATE '2023-09-04', DATE '2023-09-04', 'HNX 2023 observed National Day closure; https://www.hnx.vn/vi-vn/m-tin-tuc-hnx/Thong%20bao%20ve%20viec%20cong%20bo%20lich%20nghi%20giao%20dich%20trong%20nam%202023-60015701-1.html'),

        (DATE '2024-01-01', DATE '2024-01-01', 'HNX 2024 New Year closure; https://www.hnx.vn/vi-vn/m-tin-tuc-hnx/Thong%20bao%20ve%20viec%20cong%20bo%20lich%20nghi%20giao%20dich%20trong%20nam%202024-60017878-1.html'),
        (DATE '2024-02-08', DATE '2024-02-14', 'HNX 2024 Lunar New Year closure; https://www.hnx.vn/vi-vn/m-tin-tuc-hnx/Thong%20bao%20ve%20viec%20cong%20bo%20lich%20nghi%20giao%20dich%20trong%20nam%202024-60017878-1.html'),
        (DATE '2024-04-18', DATE '2024-04-18', 'HNX 2024 Hung Kings Day closure; https://www.hnx.vn/vi-vn/m-tin-tuc-hnx/Thong%20bao%20ve%20viec%20cong%20bo%20lich%20nghi%20giao%20dich%20trong%20nam%202024-60017878-1.html'),
        (DATE '2024-04-29', DATE '2024-05-01', 'HNX adjusted 2024 Reunification and Labour Day closure; https://www.hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60018631.html?_page=1'),
        (DATE '2024-05-04', DATE '2024-05-04', 'HNX states no securities trading on the 2024 makeup Saturday; https://www.hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60018631.html?_page=1'),
        (DATE '2024-09-02', DATE '2024-09-03', 'HNX 2024 National Day closure; https://www.hnx.vn/vi-vn/m-tin-tuc-hnx/Thong%20bao%20ve%20viec%20cong%20bo%20lich%20nghi%20giao%20dich%20trong%20nam%202024-60017878-1.html'),

        (DATE '2025-01-01', DATE '2025-01-01', 'HNX 2025 New Year closure; https://hnx.vn/en-gb/chi-tiet-lich-nghi-gd-60020153.html?_page=1'),
        (DATE '2025-01-27', DATE '2025-01-31', 'HNX 2025 Lunar New Year closure; https://hnx.vn/en-gb/chi-tiet-lich-nghi-gd-60020153.html?_page=1'),
        (DATE '2025-04-07', DATE '2025-04-07', 'HNX 2025 Hung Kings Day closure; https://hnx.vn/en-gb/chi-tiet-lich-nghi-gd-60020153.html?_page=1'),
        (DATE '2025-04-30', DATE '2025-05-02', 'HNX 2025 Reunification and Labour Day closure; https://hnx.vn/en-gb/chi-tiet-lich-nghi-gd-60020153.html?_page=1'),
        (DATE '2025-09-01', DATE '2025-09-02', 'HNX 2025 National Day closure; https://hnx.vn/en-gb/chi-tiet-lich-nghi-gd-60020153.html?_page=1'),
        (DATE '2025-04-26', DATE '2025-04-26', 'HNX states no securities trading on the 2025 makeup Saturday; https://hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60020906.html?_page=1'),

        (DATE '2026-01-01', DATE '2026-01-02', 'HNX adjusted New Year closure; https://www.hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60022084.html?_page=1'),
        (DATE '2026-01-10', DATE '2026-01-10', 'HNX states no securities trading on the 2026 New Year makeup Saturday; https://www.hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60022084.html?_page=1'),
        (DATE '2026-02-16', DATE '2026-02-20', 'HNX 2026 Lunar New Year closure; https://www.gov.hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60021971.html?_page=1'),
        (DATE '2026-04-27', DATE '2026-04-27', 'HNX 2026 Hung Kings Day closure; https://www.gov.hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60021971.html?_page=1'),
        (DATE '2026-04-30', DATE '2026-05-01', 'HNX 2026 Reunification and Labour Day closure; https://www.gov.hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60021971.html?_page=1'),
        (DATE '2026-08-31', DATE '2026-09-02', 'HNX 2026 National Day closure; https://www.gov.hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60021971.html?_page=1'),
        (DATE '2026-08-22', DATE '2026-08-22', 'HNX states no securities trading on the 2026 National Day makeup Saturday; https://www.gov.hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60021971.html?_page=1')
), expanded AS (
    SELECT generate_series(start_date, end_date, interval '1 day')::date AS trade_date,
           reason
    FROM ranges
    WHERE end_date >= DATE '2018-10-01' AND start_date <= DATE '2026-10-16'
)
INSERT INTO phase1_hnx_closed_days (trade_date, reason)
SELECT trade_date, string_agg(DISTINCT reason, '; ' ORDER BY reason)
FROM expanded
WHERE trade_date BETWEEN DATE '2018-10-01' AND DATE '2026-10-16'
GROUP BY trade_date;

DO $$
DECLARE conflicts text;
BEGIN
    SELECT string_agg(c.trade_date::text, ', ' ORDER BY c.trade_date)
    INTO conflicts
    FROM core.calendar c
    JOIN phase1_hnx_closed_days h USING (trade_date)
    WHERE c.is_session;
    IF conflicts IS NOT NULL THEN
        RAISE EXCEPTION 'HNX-published closure overlaps observed session dates: %', conflicts;
    END IF;

    SELECT string_agg(o.trade_date::text, ', ' ORDER BY o.trade_date)
    INTO conflicts
    FROM core.calendar_overrides o
    JOIN phase1_hnx_closed_days h USING (trade_date)
    WHERE o.is_session;
    IF conflicts IS NOT NULL THEN
        RAISE EXCEPTION 'HNX-published closure conflicts with an explicit open override: %', conflicts;
    END IF;
END $$;

INSERT INTO core.calendar_overrides (trade_date, is_session, reason)
SELECT trade_date, false, reason
FROM phase1_hnx_closed_days
ON CONFLICT (trade_date) DO UPDATE
SET is_session = excluded.is_session,
    reason = excluded.reason;

WITH year_sources (year_num, annual_notice, adjustments) AS (
    VALUES
        (2018, 'https://hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60000674.html?_page=1', ''),
        (2019, 'https://www.hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60002874.html?_page=1', 'https://www.hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60004039.html?_page=1'),
        (2020, 'https://hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60006486.html?_page=1', ''),
        (2021, 'https://hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60010564.html?_page=1', ''),
        (2022, 'https://hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60013320.html?_page=1', ''),
        (2023, 'https://www.hnx.vn/vi-vn/m-tin-tuc-hnx/Thong%20bao%20ve%20viec%20cong%20bo%20lich%20nghi%20giao%20dich%20trong%20nam%202023-60015701-1.html', ''),
        (2024, 'https://www.hnx.vn/vi-vn/m-tin-tuc-hnx/Thong%20bao%20ve%20viec%20cong%20bo%20lich%20nghi%20giao%20dich%20trong%20nam%202024-60017878-1.html', 'https://www.hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60018631.html?_page=1'),
        (2025, 'https://hnx.vn/en-gb/chi-tiet-lich-nghi-gd-60020153.html?_page=1', 'https://hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60020906.html?_page=1'),
        (2026, 'https://www.gov.hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60021971.html?_page=1', 'https://www.hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60022084.html?_page=1; https://w.hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60023268.html?_page=1')
), open_days AS (
    SELECT calendar_day.day::date AS trade_date,
           ys.annual_notice,
           ys.adjustments
    FROM generate_series(DATE '2018-10-01', DATE '2026-10-16', interval '1 day') AS calendar_day(day)
    JOIN year_sources ys ON ys.year_num = extract(year FROM calendar_day.day)::int
    WHERE extract(isodow FROM calendar_day.day) BETWEEN 1 AND 5
      AND NOT EXISTS (
          SELECT 1 FROM phase1_hnx_closed_days closed
          WHERE closed.trade_date = calendar_day.day::date
      )
)
INSERT INTO core.calendar AS existing (trade_date, is_session, source, notes)
SELECT trade_date,
       true,
       'hnx_official_weekday_schedule',
       concat(
           'HNX stock-market weekday rule (Monday-Friday except public holidays and management closures); guide: ',
           'https://owa.hnx.vn/ftp/PORTALNEW/PUBLICFACTBOOK_FA/20190911/HNX%20Guide%20to%20trading%20stocks.pdf',
           '; annual notice: ', annual_notice,
           CASE WHEN adjustments = '' THEN '' ELSE '; adjustment notice(s): ' || adjustments END
       )
FROM open_days
ON CONFLICT (trade_date) DO UPDATE
SET is_session = excluded.is_session,
    source = CASE
        WHEN position('hnx_official_weekday_schedule' IN existing.source) > 0 THEN existing.source
        ELSE concat_ws('+', nullif(existing.source, ''), 'hnx_official_weekday_schedule')
    END,
    notes = CASE
        WHEN position('HNX stock-market weekday rule' IN coalesce(existing.notes, '')) > 0 THEN existing.notes
        ELSE concat_ws('; ', nullif(existing.notes, ''), excluded.notes)
    END;

COMMIT;
