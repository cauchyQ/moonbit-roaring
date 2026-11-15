# Baseline benchmark (2026-11-15)

Command: `moon bench --release --deny-warn` on Windows, MoonBit compiler
`v0.10.19+bee578715`, default Wasm target. Each reported value is the mean of
10 batches, as reported by `moon bench`. The fixtures contain 6,000 IDs each:
`3*i` and `5*i+1`, for `0 <= i < 6000`.

| Workload | Mean | Standard deviation |
| --- | ---: | ---: |
| Search filter intersection and count | 311.94 µs | 8.81 µs |
| Permission union followed by exclusion and count | 110.59 µs | 6.04 µs |
| Analytics cohort intersection and count | 330.14 µs | 31.44 µs |

The search and analytics entries execute the same intersection with identical
fixtures; their measured difference is noise, not a difference in algorithms.
This is a local microbenchmark, not an end-to-end application, comparison with
other libraries, memory measurement, or a claim of speedup. The workload does
not measure portable encoding, incremental transfer, or checksum costs.

## Full versus incremental refresh

Actual run: `moon bench --release --deny-warn`, same compiler and Wasm target.
Fixture: IDs [0,10000) plus UInt32 max; target deletes [100,110) and adds
[20000,20010). The filter contains [0,5000). Search and cohort analysis use
intersection; permissions use exclusion. Three entries share a fixture to
keep refresh costs comparable. This is a controlled library workload, not
a live search server or authorization service.

| Scenario | Full receive + query | Delta receive + hashes + query | Full production | Delta production + hashes |
| --- | ---: | ---: | ---: | ---: |
| Search | 390.16 µs | 1.64 ms | 281.36 µs | 1.60 ms |
| Permissions | 340.26 µs | 1.65 ms | 287.64 µs | 1.31 ms |
| Analytics | 320.07 µs | 1.64 ms | 289.85 µs | 1.56 ms |

Full wire size: 8,218 bytes; delta wire size: 196 bytes including identity,
versions, SHA-256 digests and both portable payloads. The delta saves about
97.6% of transfer bytes in this fixture, but consumes substantially more CPU
because both baseline and reconstructed target are hashed. Choose a full
refresh when CPU cost dominates. No network latency, process startup or disk
I/O is included. No runtime heap-memory measurement was performed.

Raw output, including standard deviations and sample counts, is retained in
`scenario-benchmark-output.txt`. Correctness is checked before timed loops.
