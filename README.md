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

Add the published library to your MoonBit project:

```sh
moon add cauchyQ/moonbit-roaring@0.3.0
```

Import `"cauchyQ/moonbit-roaring" @roaring` in your `moon.pkg`.

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
moon run cmd/scenarios
```

The scenarios command checks search intersection, inherited permissions with
denial, cohort overlap, high-bit IDs, patch baseline rejection and portable
snapshot recovery. It also generates a reproducible 10,000-ID sparse index,
removes 100 IDs, checks patch replay and full snapshot recovery. Expected
counts are 2, 2 and 2, version 2, then 9,900 remaining IDs.

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
- `encode_run_words` and `decode_run_words` provide a second deterministic
  format for interval-heavy data: `[3, cardinality, run_count, start, length,
  ...]`. Decoding is bounded to 1,000,000 materialized members and rejects
  overflow, overlap, and adjacent runs that would be non-canonical.
- Union, intersection, difference, and xor merge high-16-bit blocks first and
  dispatch matching keys to container-local operations. When both containers
  are dense bitmaps, the operation runs word-wise and downshifts a sparse
  result back to Array/Run storage.
- Point membership, extrema, `rank`, and `select` stay at block/container
  level. `contains_range`, `next_at_or_after`, and `previous_at_or_before`
  build range and navigation queries from those primitives without allocating
  a temporary range bitmap.
- `stats` and `block_stats` expose cardinality and selected container kinds for
  diagnostics, without exposing mutable container storage.
- `diff_to` produces an immutable `RoaringPatch` containing additions and
  removals. A patch can be applied, inverted, and inspected for the values it
  touches, which supports incremental index and cache updates.

## 日志与回放：0.2.0 修复说明

`RoaringOperationLog` 以检查点和有序操作记录表示集合历史。追加操作时会复制
`AddAll`、`RemoveAll` 的整数数组；`operations()` 和 `operation_at()` 也返回
独立副本。修改调用方数组或读取接口返回的数组，不会改变原日志、其编码或派生分支。

日志允许保存尚未执行的操作。`replay()` 按顺序执行，遇到非法操作就返回错误，
不会把部分执行结果当作完整结果。历史接口遵守同样的规则：

- `replay_prefix(count)` 只执行指定前缀；有效前缀可以成功，前缀中的操作失败则返回错误。
- `split_at(count)` 先回放前缀，成功后才建立后缀检查点；失败前缀不能被回退成旧检查点。
- `cardinality_history()` 返回 `Result[Array[Int], JournalRangeError]`，遇到失败立即停止。
- `OperationFailed(index, cause)` 保留相对于当前日志的零基操作位置及原始 `RoaringError`；
  请求位置越界时仍返回 `InvalidIndex`。

例如 `[Add(1), Add(-1), Add(2)]` 的前两项回放和 `split_at(2)` 都应失败。
只回放第一项可以成功；此时拆出的后缀仍包含失败操作，不能成功完整回放。
失败操作不会改变原日志和检查点。

**从 0.1.0 迁移：** `cardinality_history()` 原先直接返回数组，现在需要处理 `Ok` / `Err`。
对于已知有效的测试数据，可使用 `log.cardinality_history().unwrap()`；业务代码应处理
`OperationFailed`。如果对 `JournalRangeError` 做穷尽匹配，也需要补上新增的错误分支。
日志整数词编码的版本和标签没有改变，本次未引入新的编码格式。

`journal_regression_test.mbt` 覆盖输入与输出数组隔离、分支和拆分隔离、失败位置、
非法批次、无效前缀、历史统计和编码往返。全部测试在普通及 Release 模式下运行。
CI 固定编译器 `v0.10.19+bee578715`。

The test suite includes fixed boundary tests plus a deterministic 64-case
property corpus covering commutativity, idempotence, cancellation, and
encode/decode round trips. `roaring_bench.mbt` contains reproducible dense
block workloads for `moon bench`; its numbers are measurements for the local
toolchain and machine, not portable performance claims.

## Scope and provenance

The `serialize_portable` and `decode_portable` APIs use
[`xcc-ordinary/moonbit-roaring` 0.1.0](https://github.com/xcc-ordinary/moonbit-roaring),
an Apache-2.0 dependency, for Roaring portable encoding. The adapter currently
accepts only values in the existing non-negative `Int` domain and rejects
portable inputs containing higher unsigned values. Conversion materializes
the members; it is not a streaming codec. A fixed sparse fixture generated by
pyroaring 1.2.0 (which uses CRoaring) is checked in `portable_test.mbt`;
additional cross-language cases are exercised by the verification script.

Run `python verify_croaring.py` with `pyroaring==1.2.0` to validate MoonBit
portable output using the independent CRoaring reader (10,002 members,
including unsigned high-bit IDs). The inverse direction uses the fixed
CRoaring fixtures in `portable_test.mbt` and `uint32_bitmap_test.mbt`.

`UInt32Bitmap` provides an experimental unsigned API with four independent
shards and a UInt64 cardinality. Its portable writer processes individual
containers; conversion buffers hold at most 65,536 members. The former
one-million-member codec limit has been removed and a 1,000,001-member round
trip is covered by a regression test. The unsigned API
supports half-open UInt64 ranges including the endpoint 2^32. `UInt32Snapshot`
provides a checked patch using dataset name, generation and SHA-256 content
digests. `UInt32SnapshotPatch::serialize` writes the versioned `URP1` wire
format containing two portable bitmap deltas, without retaining complete
baseline or target bitmaps. `decode_uint32_patch` validates framing and dataset.
The unsigned API does not yet offer the journal interface.

Run `moon bench --release --deny-warn` for full versus incremental refresh
comparisons including digest costs; see [BENCHMARKS.md](BENCHMARKS.md).

This is an independent MoonBit implementation inspired by the Roaring Bitmap
data-structure family and the public design of CRoaring. Independently generated
CRoaring fixtures test interoperability. No CRoaring source, SIMD routine or
API is copied here. CRoaring is
Apache-2.0 licensed; see <https://github.com/RoaringBitmap/CRoaring>.

The original API accepts non-negative `Int` values. `UInt32Bitmap` supports
unsigned values; cross-target boundary coverage remains to be verified.
`serialize_portable_compact()` emits Run containers where they reduce encoded
size. `serialize_portable()` remains the canonical encoding for URP1 digests.

## License

Apache-2.0; the complete text is in [LICENSE](LICENSE).
