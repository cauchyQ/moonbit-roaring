# MoonBit Roaring

MoonBit Roaring is a pure-MoonBit compressed integer-set library. It partitions
non-negative `Int` values by their high 16 bits and represents each partition
as a sorted array, a fixed bitmap, or consecutive runs. It is an index data
structure, not a database, search engine, or permission service.

## Why

Search filters, access-control sets, and analytical cohorts repeatedly need
union, intersection, difference, rank, and select over integer identifiers.
A plain `Array[Int]` wastes work for dense values; a flat bitset wastes memory
for sparse values. Roaring-style containers choose a representation per block.

## Use

```moonbit
let left = @roaring.RoaringBitmap::from_array([1, 2, 3, 70_000]).unwrap()
let right = @roaring.RoaringBitmap::from_array([2, 3, 80_000]).unwrap()
assert_eq(left.intersection(right).to_array(), [2, 3])
```

Run checks and the example:

```text
moon check --deny-warn
moon test --deny-warn
moon bench --release --deny-warn
moon run cmd/main
```

## Implemented API boundaries

- `from_range`, `add_range`, and `remove_range` use half-open ranges and reject
  negative and inverted endpoints. Constructing or adding a range longer than
  1,000,000 values is rejected because it materializes new members; removing a
  range has no such cap because it only scans members already stored.
- `add_all` and `remove_all` validate a whole batch before returning a new,
  immutable bitmap; invalid input returns an error rather than silently
  changing the batch.
- `from_ranges`, `add_ranges`, and `remove_ranges` accept batches of half-open
  intervals and normalize overlap. `to_ranges` returns a canonical interval
  cover; it explicitly rejects the unrepresentable half-open endpoint after
  the maximum `Int`.
- `cursor().next()` traverses values in ascending order without exposing the
  internal container representation, loading one container at a time rather
  than copying the complete bitmap at cursor creation.
- `union_all`, `intersection_all`, and `xor_all` aggregate an array of bitmap
  operands with explicit empty-input identities, for multi-filter queries.
- `RoaringBuilder` stages validated values, batches, and bounded inserted
  ranges, then performs one normalization at `finish`; this is the preferred
  ingestion path when values arrive incrementally.
- `encode_words` and `decode_words` implement a deterministic, versioned word
  encoding: `[1, cardinality, ..strictly_ascending_values]`. The decoder
  rejects bad versions, incorrect lengths, negative values, duplicates, and
  non-canonical order. This is deliberately *not* CRoaring binary format.
- Union, intersection, difference, and xor merge high-16-bit blocks first and
  dispatch matching keys to container-local operations.
- Point membership, extrema, `rank`, and `select` stay at block/container
  level. `contains_range`, `next_at_or_after`, and `previous_at_or_before`
  build range and navigation queries from those primitives without allocating
  a temporary range bitmap.

The test suite includes fixed boundary tests plus a deterministic 64-case
property corpus covering commutativity, idempotence, cancellation, and
encode/decode round trips. `roaring_bench.mbt` contains reproducible dense
block workloads for `moon bench`; its numbers are measurements for the local
toolchain and machine, not portable performance claims.

## Scope and provenance

This is an independent MoonBit implementation inspired by the Roaring Bitmap
data-structure family and the public design of CRoaring. No CRoaring source,
test corpus, binary format, SIMD routine, or API is copied here. CRoaring is
Apache-2.0 licensed; see <https://github.com/RoaringBitmap/CRoaring>.

The initial API accepts non-negative MoonBit `Int` values. It intentionally
does not claim the complete unsigned-32-bit API until a public `UInt` API and
cross-target boundary tests are implemented.

## License

Apache-2.0; the complete text is in [LICENSE](LICENSE).
