# Secret scanner result — Google-key-shaped Base64 false positive

Rechecked: 2026-10-30

The potential Google API key alert points to a 39-character `AIza...`-shaped
substring in the `body_b64` field for
`NSC_HOSE_first_day_notice_2021-08-30.pdf` in parent commit `68f44cb`. The
field is a Base64 encoding of the PDF, not a credential field.

The current `body_hex` row decodes to exactly the same bytes as the committed
Base64 row. The old Base64-decoded bytes, current hex-decoded bytes, and local
source PDF all match SHA-256
`5641fbcac616bcbdef1623912bc5cee2e24fc79a64e9072981256f98c4d27139` and the
declared size of 710,412 bytes. The raw PDF contains no `AIza` prefix and no
full Google-key-shaped match. All 14 current landing-stage rows match their
declared sizes and SHA-256 values; their hex representation has zero such
matches.

This is a Base64 false positive. No live key validation or Google API request
was made, and no credential rotation is indicated by this evidence. The
historical commit remains in Git, so a host-side alert may persist; if it
references this match, classify it as a false positive. The history was not
rewritten.
