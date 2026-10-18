-- Keep index histories independently attributed when two providers are stored.
BEGIN;

ALTER TABLE core.index_bars DROP CONSTRAINT IF EXISTS index_bars_pkey;
ALTER TABLE core.index_bars
    ADD CONSTRAINT index_bars_pkey PRIMARY KEY (index_symbol, trade_date, source);

COMMIT;
