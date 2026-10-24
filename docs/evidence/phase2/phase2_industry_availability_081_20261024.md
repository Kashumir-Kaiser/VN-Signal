# Industry classification availability — migration 081

The overlay previously selected `listing_snapshots.snapshot_date <= signal_date`.
That table has no collection timestamp, so it could expose an after-close pull
to the same day's bank metrics and peer ranks. The V3 price builder does not use
this lookup; its running build and feature formula identity are unaffected.

The overlay now uses `core.industry_as_of`: the latest security observation
whose observation date is no later than signal and whose timestamp is no later
than the local 15:00 cutoff. Unknown classification, delisted category or
conflicting classifications at that latest instant return NULL without falling
back to an older known industry. It persists the observation IDs and availability
and includes industry raw landing IDs in source lineage. Mapping identity adds
`industry_observations=v1`. The fundamentals chunk manifest now hashes these
timestamped observations instead of date-only listing snapshots.

Targeted migration apply/replay and the full fundamental assertions pass in the
disposable 076 review database. Source-linked synthetic industry fixtures replace
the old snapshot-based classification inputs. Dedicated checks in
`phase2_industry_availability_081_edges_20261024.log` verify after-close exclusion,
next-day visibility, same-instant conflict, missing/unknown inputs, persisted
bank suppression and lineage, and cutoff-sensitive input-hash invalidation.
No vendor route is called. Go tests/vet and all 32 Python tests pass in the081
logs. Full fresh migration harness and report application are queued serially
after the real feature build; these are not yet claimed complete.
