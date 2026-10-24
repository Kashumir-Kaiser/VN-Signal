# Fundamental archive JSON-type validation — 2026-10-24

The analyzer previously accepted quoted numeric JSON through json.Number, and accepted non-string unit values. The archive expects numeric level/order/value fields and an integer order representable by PostgreSQL integer. Invalid frames could therefore pass analysis and fail at commit rather than enter the existing quarantine path.

The analyzer now rejects quoted numeric fields, fractional/non-integer order tokens, out-of-range signed32-bit orders, and non-string/non-null units. Unknown/null units remain archived without implying a verified metric mapping. Plain integer order boundaries are covered. The validated input contract currently requires integer order tokens; fresh provider capability checks must establish the actual representation before enabling ingestion.

Go tests, Go vet and all31 Python tests passed after formatting (go_test_fundamental_types_20261024.log, go_vet_fundamental_types_20261024.log, python_tests_fundamental_types_20261024.log). No worker change or live route call. No mappings were guessed or enabled; real statement capability evidence is still missing.
