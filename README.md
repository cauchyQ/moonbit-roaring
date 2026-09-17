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
moon run cmd/main
```

## Scope and provenance

This is an independent MoonBit implementation inspired by the Roaring Bitmap
data-structure family and the public design of CRoaring. No CRoaring source,
test corpus, binary format, SIMD routine, or API is copied here. CRoaring is
Apache-2.0 licensed; see <https://github.com/RoaringBitmap/CRoaring>.

The initial API accepts non-negative MoonBit `Int` values. It intentionally
does not claim the complete unsigned-32-bit API until a public `UInt` API and
cross-target boundary tests are implemented.

## License

Apache-2.0. The repository will include the full license text before release.
