# Corporate-action price-basis probe

Probe date: 2026-10-18; KBS follow-up: 2026-10-19 (Vietnam time). The initial
check covered VCI's 10:3 bonus-share issue. A follow-up below adds a separate
cash-dividend event, official vnstock documentation, and source-specific price
basis classifications. Neither event establishes the point-in-time
availability of restated historical prices.

## Event evidence

Vietcap's issuer notice states a 10:3 bonus-share ratio and a final
registration date of 2024-09-13. The archived primary PDF is
`vietcap-vci-bonus-issue-notice-2024-08-28.pdf` (SHA-256
`34e46e9fb9eac6325f6210eb97a438aa0897e1695751fe38e313ecce231791b5`). The
broker's 2024-09-12 report labels the reference price as adjusted; its archived
PDF is `shs-vci-market-report-2024-09-12.pdf` (SHA-256
`5a317636d57e0b1e8dceb4be07259c73981a3587f0d30d6c0797996e2c2b90bc`).

The [Vnstock OHLCV documentation](https://www.vnstocks.com/docs/vnstock/thi-truong-market)
says stock prices are adjusted for rights and warns that VCI and KBS can show
different historical prices after rights events.

## Event-day observations

| Source | 2024-09-11 close / volume | 2024-09-12 close / volume | What this establishes |
| --- | --- | --- | --- |
| VCI canonical | 24.24 / 6,399,940 | 24.03 / 6,133,538 | Aligns with the adjusted-price branch for this event; the later FPT cash-dividend check classifies its OHLC prices as adjusted. |
| DNSE alternate | 24.25 / 6,398,800 | 24.03 / 6,129,900 | Also aligns with the adjusted-price branch for this event; the later FPT cash-dividend check classifies its OHLC prices as adjusted. |
| VNDIRECT raw fields | 43.80 / 6,398,800 | 33.40 / 6,129,900 | Raw `o/h/l/c` stay unadjusted; the archived responses also provide separate `ad*` values now materialized by migration 026. |
| CafeF public history | raw 43.80; adjusted 24.25 / 6,398,800 | raw 33.40; adjusted 24.04 / 6,129,900 | Independent raw and adjusted close fields cross-check the event. |
| EasyStock public JSON | 24.26 / 6,398,800 | 24.04 / 6,129,900 | Appears adjusted for this event; point-in-time basis is undocumented. |

The [Cophieu68 event calculation](https://cophieu68.vn/quote/event_calc.php?id=vci)
reports a 1.3 factor, a 43.80 previous close, a 33.69 theoretical ex-right
reference, and a 33.40 market close. Its backwards-adjusted close is 24.04.
These observations show why mixing raw VNDIRECT prices with the VCI/DNSE
series would create a false event return. Differences of 0.01–0.02 between
adjusted providers remain source differences; they are not grounds to rewrite
the database.

The raw volume figures are not multiplied by 1.3 in this sample. This does
not establish a provider-wide volume-adjustment rule. Volume basis and full
corporate-action treatment remain unresolved.

## Database lineage and limits

- VCI raw landing 4621, SHA-256
  `1168f2b19933b6e3969b98e1804ba0a3105f46578c3ad74595ee86361d068317`, contains
  2024-09-11 and 2024-09-12 at source rows 1472 and 1473 (zero-based).
- DNSE raw landing 6663, SHA-256
  `eaa7733dda5bc4b86a1fcc958659622f7d6139eb357f361e47d58229f1a25377`, contains
  those sessions at source rows 1485 and 1486.
- VNDIRECT raw landing 8187, SHA-256
  `fc37d8e4f17623ab624a9220b50f274098e83ef2ae19b8306dc9bb6a18ae2310`, contains
  those sessions at source rows 1485 and 1486.
- CafeF's two-row response is `cafef-vci-event-2024-09-11-12.json` (SHA-256
  `c4afa2088b050a05d3fc49f3f6d9a29f75ca5f01896e14472f18ba2b0a735359`).
- EasyStock's full VCI response is
  `../phase1-easystock/VCI.json` (SHA-256
  `d6711eee27dfa5a43a7be6cf5ce8570d30a299905ade28aa509f9fd25764af75`).

### Follow-up: FPT cash-dividend event and source-basis classification

VSDC's 2024-11-22 notice records a VND 1,000/share cash dividend and a
2024-12-03 record date. The HOSE-hosted announcement identifies 2024-12-02 as
the ex-right date. In the archived source responses, FPT's raw VNDIRECT close
was 144.3 thousand VND on 2024-11-29 and 142.2 thousand VND on 2024-12-02.
Removing the 1.0-thousand dividend from the prior close gives a dividend-aware
return of 142.2 / (144.3 - 1.0) - 1 = -0.7676%; the unadjusted close return is
-1.4553%.

On those same sessions, VCI closes were 109.66 and 108.81, DNSE closes were
109.65 and 108.81, and VNDIRECT's separately supplied adjusted closes were
109.658 and 108.813 thousand VND. Their returns are -0.7751%, -0.7661%, and
-0.7706%, respectively. VCI's two-decimal output and the source's own event
rounding explain the small residual differences. These independent values
match the cash-dividend-adjusted branch, rather than the raw-price return.
Row values, zero-based source rows, raw landing IDs, and exact response hashes
are in [`fpt-cash-dividend-cross-source.csv` (local evidence file `fpt-cash-dividend-cross-source.csv`; not published).
The CSV SHA-256 is `1A08519ED89E1E30F455C11B416494C0892DB549598409DE6A0C6F619EF86F67`.

Two successful registered-machine KBS probes cover the same FPT event. The
KBS default OHLCV response (`raw_prices=false`) returned close 109.72 on
2024-11-29 and 108.88 on 2024-12-02, with volumes 11,586,700 and 6,616,800.
Those volumes match the local VNDIRECT and DNSE rows. The KBS close return is
108.88 / 109.72 - 1 = -0.7656%; it follows the dividend-adjusted branch and
is far from the raw VNDIRECT close return (-1.4553%). KBS differs from VCI and
DNSE by a few cents, consistent with vnstock's warning that providers can
return different adjusted prices after rights events. The compact probe
reports and their hashes are in
[`phase1-current-kbs-verify/README.md`](../phase1-current-kbs-verify/README.md).

VNDIRECT's own DStock price-history page says its adjusted close accounts for
share splits and cash dividends on ex-right dates and is used in its technical
chart. HOSE-hosted FPT warrant disclosure identifies 2024-12-02 as the
ex-right date and gives the underlying reference-price change from 144.300 to
143.300, matching the VNDIRECT raw close less the VND 1.000/share dividend.
The archived FPT API row's `adClose` agrees with the dividend-adjusted branch.
See [VNDIRECT's price-history explanation](https://dstock.vndirect.com.vn/lich-su-gia/VND)
and the [HOSE-hosted FPT adjustment disclosure](https://staticfile.hsx.vn/Uploads/UploadDocuments/2374370/20250514%20-%20CFPT2407%20-%20BCB%20chao%20ban%20bo%20sung%20lan%201.pdf).

Keep VNDIRECT ordinary OHLC in raw `o/h/l/c` with `adj_basis='unadjusted'`;
migration 026 stores the provider's separate `ad*` OHLC snapshot and its fetch
time in dedicated columns. `core.vndirect_bars_as_of` converts that retrospective
snapshot to the requested historical date basis and fails closed when the rows
through that date do not share one complete snapshot vintage. Do not write
adjusted values over raw fields. The function solves the VNDIRECT vintage only;
VCI, DNSE, and KBS still need their own point-in-time vintage handling before
cross-source feature joins. KBS's 495 completed full-range responses remain raw
landings and have not been materialized in `core.bars_daily_sources`. The labels
concern prices only; this event does not establish a provider-wide
volume-adjustment rule.

Two earlier exact-date KBS probes timed out. The successful 2026-10-19
follow-up retrieved the two event dates and saved compact target-row reports.
All three calls used the Go metered probe gateway with a fresh authenticated
quota check; the probes did not alter market data tables.

This does **not** establish when a provider first applied later rights to an
old bar. The responses fetched in 2026 contain retrospectively adjusted
history, so VCI, DNSE, and KBS bars remain unsuitable for point-in-time
training until the action-adjustment vintage is reconstructed as of each
historical signal date. Keep provider histories separate; do not rewrite
OHLCV or imply that the basis label alone solves point-in-time availability.

## Sources

- [Vietcap issuer notice](https://www.vietcap.com.vn/api/cms-api/uploads/froala/files/20240828%20-%20VCI%20-%20TB%20Ve%20ngay%20dang%20ky%20cuoi%20cung%20de%20thuc%20hien%20PH%20co%20phieu%20de%20tang%20von%20co%20phan%20tu%20nguon%20von%20CSH.pdf)
- [SHS market report, 2024-09-12](https://www.shs.com.vn/Sites/QuoteVN/SiteRoot/reportattach/20240912_173649_Market_Lens_Final_New_12-09-2024.pdf)
- [Vnstock OHLCV documentation](https://www.vnstocks.com/docs/vnstock/thi-truong-market)
- [VSDC FPT first advance payment of 2024 cash dividend](https://vsdc.vn/en/ad/176881)
- [HOSE-hosted document identifying the 2024-12-02 FPT ex-right date](https://staticfile.hsx.vn/Uploads/UploadDocuments/2374370/20250514%20-%20CFPT2407%20-%20BCB%20chao%20ban%20bo%20sung%20lan%201.pdf)
- [CafeF historical-price page](https://cafef.vn/du-lieu/lich-su-giao-dich-api-4.chn)
- [Cophieu68 VCI event calculation](https://cophieu68.vn/quote/event_calc.php?id=vci)
- [EasyStock free OHLCV download page](https://easystock.vn/easystock-download-en.html)
