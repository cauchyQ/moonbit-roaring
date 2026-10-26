///|
test "catalog traced evaluation distinguishes missing labels from empty results" {
  let universe = @moonbit-roaring.RoaringBitmap::from_array([1, 2, 3, 4]).unwrap()
  let catalog = @moonbit-roaring.BitmapCatalog::new()
    .upsert(10, @moonbit-roaring.RoaringBitmap::from_array([1, 2]).unwrap())
    .upsert(20, @moonbit-roaring.RoaringBitmap::new())
  let traced = catalog.evaluate_traced(
    Any([Key(10), Key(20), Key(99), Key(99)]),
    universe,
  )
  assert_eq(traced.bitmap.to_array(), [1, 2])
  assert_eq(traced.missing_keys, [99])
  assert_eq(catalog.remove(10).keys(), [20])
}

///|
test "catalog empty query identities are explicit against its universe" {
  let universe = @moonbit-roaring.RoaringBitmap::from_array([1, 2, 3]).unwrap()
  let catalog = @moonbit-roaring.BitmapCatalog::new()
  assert_true(catalog.evaluate(Any([]), universe).is_empty())
  assert_eq(catalog.evaluate(All([]), universe).to_array(), [1, 2, 3])
  assert_eq(catalog.evaluate(AtLeast(0, []), universe).to_array(), [1, 2, 3])
  assert_true(catalog.evaluate(AtLeast(1, []), universe).is_empty())
}

///|
test "operation log batch audit and pending patch preserve checkpoint semantics" {
  let checkpoint = @moonbit-roaring.RoaringBitmap::from_array([1, 3, 5]).unwrap()
  let log = @moonbit-roaring.RoaringOperationLog::new(checkpoint).append_all([
    Add(2),
    Remove(5),
    AddRange(7, 9),
  ])
  assert_eq(log.operations().length(), 3)
  assert_eq(log.checkpoint().to_array(), [1, 3, 5])
  let patch = log.pending_patch().unwrap()
  assert_eq(patch.apply(checkpoint).to_array(), [1, 2, 3, 7, 8])
  assert_eq(log.compact().unwrap().checkpoint().to_array(), [1, 2, 3, 7, 8])
}

///|
test "frame checksums cover both codec formats and retain format boundaries" {
  let sparse = @moonbit-roaring.RoaringBitmap::from_array([1, 9, 17, 90_000]).unwrap()
  let plain = sparse.frame(PlainWords).unwrap()
  let runs = sparse.frame(RunWords).unwrap()
  assert_eq(plain.decode().unwrap().to_array(), sparse.to_array())
  assert_eq(runs.decode().unwrap().to_array(), sparse.to_array())
  let modified = plain.with_payload([1, 4, 1, 9, 17, 90_001])
  assert_true(modified.decode() is Err(ChecksumMismatch(_, _)))
}

///|
test "transform positional operations respect empty and out of range requests" {
  let bitmap = @moonbit-roaring.RoaringBitmap::from_array([10, 20, 30]).unwrap()
  assert_true(bitmap.take(-1).is_empty())
  assert_eq(bitmap.drop(-1).to_array(), [10, 20, 30])
  assert_true(bitmap.slice_positions(9, 11).unwrap().is_empty())
  assert_true(bitmap.slice_positions(-1, 1) is Err(InvalidRange(-1, 1)))
  assert_eq(
    bitmap.map_values(value => value).unwrap().to_array(),
    bitmap.to_array(),
  )
  assert_true(bitmap.map_values(_ => -1) is Err(NegativeValue(-1)))
}

///|
test "analytics handles empty sets and rational quantile endpoints" {
  let empty = @moonbit-roaring.RoaringBitmap::new()
  assert_eq(empty.profile().span, 0)
  assert_eq(empty.density_parts(), (0, 0))
  assert_eq(empty.sample_evenly(4), [])
  assert_eq(empty.sample_stride(1), [])
  assert_true(empty.quantile(0, 1) is Ok(None))
  let bitmap = @moonbit-roaring.RoaringBitmap::from_array([2, 4, 6, 8]).unwrap()
  assert_true(bitmap.quantile(0, 3) is Ok(Some(2)))
  assert_true(bitmap.quantile(3, 3) is Ok(Some(8)))
  assert_true(bitmap.quantile(1, 0) is Err(InvalidRange(1, 0)))
}

///|
test "plan description remains stable across binary and unary nodes" {
  let source = @moonbit-roaring.BitmapPlan::Source(
    @moonbit-roaring.RoaringBitmap::from_array([1, 2, 3]).unwrap(),
  )
  let plan = @moonbit-roaring.BitmapPlan::Drop(
    @moonbit-roaring.BitmapPlan::Take(source, 2),
    1,
  )
  assert_eq(plan.evaluate().to_array(), [2])
  assert_eq(plan.describe(), "drop(1,take(2,source(3)))")
  let stats = plan.stats()
  assert_eq(stats.nodes, 3)
  assert_eq(stats.depth, 3)
  assert_eq(stats.sources, 1)
}

///|
test "range APIs agree with rank select and cursor traversal" {
  let bitmap = @moonbit-roaring.RoaringBitmap::from_ranges([
    { start: 0, end: 3, },
    { start: 10, end: 14, },
    { start: 65_535, end: 65_538, },
  ]).unwrap()
  assert_eq(bitmap.cardinality(), 10)
  assert_eq(bitmap.rank(2), 3)
  assert_eq(bitmap.rank(9), 3)
  assert_eq(bitmap.rank(10), 4)
  assert_eq(bitmap.select(9), Some(65_537))
  assert_eq(bitmap.next_at_or_after(3), Some(10))
  assert_eq(bitmap.previous_at_or_before(64_000), Some(13))
  assert_true(bitmap.contains_range(10, 14) is Ok(true))
  assert_true(bitmap.contains_range(2, 11) is Ok(false))
  let cursor = bitmap.cursor()
  let (_, cursor) = cursor.next()
  let (_, cursor) = cursor.next()
  let (third, cursor) = cursor.next()
  assert_eq(third, Some(2))
  assert_eq(cursor.remaining(), 7)
}

///|
test "batch mutation matches independently applied operations" {
  let base = @moonbit-roaring.RoaringBitmap::from_array([1, 3, 5, 7]).unwrap()
  let bulk = base.add_all([2, 4, 6, 8]).unwrap().remove_all([1, 8]).unwrap()
  let stepwise = base
    .add(2)
    .unwrap()
    .add(4)
    .unwrap()
    .add(6)
    .unwrap()
    .add(8)
    .unwrap()
    .remove(1)
    .remove(8)
  assert_eq(bulk.to_array(), stepwise.to_array())
  let range_bulk = base
    .add_ranges([{ start: 10, end: 13, }, { start: 12, end: 15, }])
    .unwrap()
  assert_eq(range_bulk.to_array(), [1, 3, 5, 7, 10, 11, 12, 13, 14])
  assert_eq(
    range_bulk.remove_ranges([{ start: 3, end: 13, }]).unwrap().to_array(),
    [1, 13, 14],
  )
}

///|
test "codec conversions retain canonical forms for sparse dense and run data" {
  let sparse = @moonbit-roaring.RoaringBitmap::from_array([1, 99, 70_000]).unwrap()
  let dense = @moonbit-roaring.RoaringBitmap::new().add_range(0, 5_000).unwrap()
  let runs = @moonbit-roaring.RoaringBitmap::from_ranges([
    { start: 5, end: 45, },
    { start: 100, end: 120, },
  ]).unwrap()
  for bitmap in [sparse, dense, runs] {
    let plain = bitmap.encode(PlainWords).unwrap()
    let run = bitmap.encode(RunWords).unwrap()
    assert_eq(
      @moonbit-roaring.decode_auto(plain).unwrap().to_array(),
      bitmap.to_array(),
    )
    assert_eq(
      @moonbit-roaring.decode_auto(run).unwrap().to_array(),
      bitmap.to_array(),
    )
    assert_eq(
      @moonbit-roaring.transcode(plain, PlainWords, RunWords).unwrap(),
      run,
    )
    assert_eq(
      @moonbit-roaring.transcode(run, RunWords, PlainWords).unwrap(),
      bitmap.encode_words(),
    )
  }
}

///|
test "mixed container algebra obeys distributive and cancellation laws" {
  let sparse = @moonbit-roaring.RoaringBitmap::from_array([
    1, 7, 65_537, 130_000,
  ]).unwrap()
  let dense = @moonbit-roaring.RoaringBitmap::new().add_range(0, 5_000).unwrap()
  let runs = @moonbit-roaring.RoaringBitmap::from_ranges([
    { start: 3_000, end: 3_100, },
    { start: 65_530, end: 65_540, },
  ]).unwrap()
  assert_eq(
    sparse.intersection(dense.union(runs)).to_array(),
    sparse.intersection(dense).union(sparse.intersection(runs)).to_array(),
  )
  assert_eq(
    sparse.difference(dense.union(runs)).to_array(),
    sparse.difference(dense).intersection(sparse.difference(runs)).to_array(),
  )
  assert_true(sparse.xor(sparse).is_empty())
  assert_eq(sparse.xor(dense).xor(dense).to_array(), sparse.to_array())
  assert_true(sparse.union(dense).validate() is Ok(_))
  assert_true(sparse.intersection(runs).validate() is Ok(_))
  assert_true(sparse.difference(runs).validate() is Ok(_))
  assert_true(sparse.xor(runs).validate() is Ok(_))
}

///|
test "invalid input paths do not expose partial immutable results" {
  let original = @moonbit-roaring.RoaringBitmap::from_array([2, 4, 6]).unwrap()
  assert_true(original.add_all([8, -1]) is Err(NegativeValue(-1)))
  assert_true(original.add_range(-1, 4) is Err(InvalidRange(-1, 4)))
  assert_true(original.add_range(4, 3) is Err(InvalidRange(4, 3)))
  assert_true(original.add_range(0, 1_000_001) is Err(RangeTooLarge(1_000_001)))
  assert_true(
    original.remove_ranges([{ start: 9, end: 3, }]) is Err(InvalidRange(9, 3)),
  )
  assert_eq(original.to_array(), [2, 4, 6])
  let builder = @moonbit-roaring.RoaringBuilder::new()
  assert_true(builder.push_all([1, 2]) is Ok(_))
  assert_true(builder.push_all([3, -7, 5]) is Err(NegativeValue(-7)))
  assert_eq(builder.staged_len(), 2)
  assert_eq(builder.finish().to_array(), [1, 2])
}

///|
test "empty and singleton bitmaps retain all public invariants" {
  let empty = @moonbit-roaring.RoaringBitmap::new()
  assert_true(empty.validate() is Ok(_))
  assert_eq(empty.minimum(), None)
  assert_eq(empty.maximum(), None)
  assert_eq(empty.select(0), None)
  assert_eq(empty.rank(0), 0)
  assert_true(empty.is_subset_of(@moonbit-roaring.RoaringBitmap::new()))
  let singleton = @moonbit-roaring.RoaringBitmap::from_array([2_147_483_647]).unwrap()
  assert_true(singleton.validate() is Ok(_))
  assert_eq(singleton.minimum(), Some(2_147_483_647))
  assert_eq(singleton.maximum(), Some(2_147_483_647))
  assert_eq(singleton.select(0), Some(2_147_483_647))
  assert_eq(singleton.rank(2_147_483_647), 1)
  assert_eq(singleton.previous_at_or_before(2_147_483_647), Some(2_147_483_647))
  assert_eq(singleton.next_at_or_after(2_147_483_647), Some(2_147_483_647))
}

///|
test "end to end catalog plan patch log and frame workflow is reproducible" {
  let universe = @moonbit-roaring.RoaringBitmap::from_range(0, 20).unwrap()
  let catalog = @moonbit-roaring.BitmapCatalog::new()
    .upsert(
      1,
      @moonbit-roaring.RoaringBitmap::from_ranges([
        { start: 0, end: 8, },
        { start: 12, end: 16, },
      ]).unwrap(),
    )
    .upsert(
      2,
      @moonbit-roaring.RoaringBitmap::from_ranges([
        { start: 4, end: 12, },
        { start: 16, end: 20, },
      ]).unwrap(),
    )
  let selected = catalog.evaluate(AtLeast(2, [Key(1), Key(2)]), universe)
  assert_eq(selected.to_array(), [4, 5, 6, 7])
  let plan = @moonbit-roaring.BitmapPlan::Union(
    @moonbit-roaring.BitmapPlan::Source(selected),
    @moonbit-roaring.BitmapPlan::Source(
      @moonbit-roaring.RoaringBitmap::from_array([18]).unwrap(),
    ),
  )
  let planned = plan.evaluate()
  let log = @moonbit-roaring.RoaringOperationLog::new(planned).append_all([
    Remove(5),
    Add(19),
  ])
  let updated = log.replay().unwrap()
  let patch = planned.diff_to(updated)
  assert_eq(patch.apply(planned).to_array(), [4, 6, 7, 18, 19])
  let encoded = updated.frame(RunWords).unwrap()
  assert_eq(encoded.decode().unwrap().to_array(), updated.to_array())
  assert_true(updated.validate() is Ok(_))
}

///|
test "catalog query metadata preserves repeated references and nesting depth" {
  let query = @moonbit-roaring.CatalogQuery::Any([
    @moonbit-roaring.CatalogQuery::Key(1),
    @moonbit-roaring.CatalogQuery::Not(
      @moonbit-roaring.CatalogQuery::All([
        @moonbit-roaring.CatalogQuery::Key(2),
        @moonbit-roaring.CatalogQuery::AtLeast(1, [
          @moonbit-roaring.CatalogQuery::Key(1),
          @moonbit-roaring.CatalogQuery::Key(3),
        ]),
      ]),
    ),
  ])
  let keys = query.referenced_keys()
  assert_eq(keys, [1, 2, 1, 3])
  let stats = query.stats()
  assert_eq(stats.nodes, 8)
  assert_eq(stats.depth, 5)
  assert_eq(stats.key_references, 4)
  let universe = @moonbit-roaring.RoaringBitmap::from_array([1, 2, 3]).unwrap()
  let catalog = @moonbit-roaring.BitmapCatalog::new()
    .upsert(1, @moonbit-roaring.RoaringBitmap::from_array([1]).unwrap())
    .upsert(2, @moonbit-roaring.RoaringBitmap::from_array([2]).unwrap())
  let traced = catalog.evaluate_traced(query, universe)
  assert_eq(traced.missing_keys, [3])
  assert_eq(traced.bitmap.to_array(), [1, 2, 3])
}

///|
test "relation helpers agree on empty sets" {
  let empty = @moonbit-roaring.RoaringBitmap::new()
  let value = @moonbit-roaring.RoaringBitmap::from_array([7]).unwrap()
  assert_true(empty.relation_to(empty) is Equal)
  assert_true(empty.relation_to(value) is ProperSubset)
  assert_true(value.relation_to(empty) is ProperSuperset)
  assert_eq(empty.overlap_coefficient_parts(value), (0, 0))
  assert_true(empty.is_disjoint(value))
  assert_eq(empty.union_cardinality(value), 1)
}

///|
test "query trace records stable key resolution and conservative bounds" {
  let universe = @moonbit-roaring.RoaringBitmap::from_array([1, 2, 3, 4, 5]).unwrap()
  let catalog = @moonbit-roaring.BitmapCatalog::new()
    .upsert(1, @moonbit-roaring.RoaringBitmap::from_array([1, 2]).unwrap())
    .upsert(2, @moonbit-roaring.RoaringBitmap::from_array([2, 3, 4]).unwrap())
  let query = @moonbit-roaring.CatalogQuery::Any([
    @moonbit-roaring.CatalogQuery::Key(1),
    @moonbit-roaring.CatalogQuery::Key(9),
    @moonbit-roaring.CatalogQuery::Key(2),
  ])
  let trace = catalog.execute_with_trace(query, universe)
  assert_eq(trace.result.to_array(), [1, 2, 3, 4])
  assert_eq(trace.requested_keys, [1, 9, 2])
  assert_eq(trace.resolved_keys, [1, 2])
  assert_eq(trace.missing_keys, [9])
  assert_eq(trace.result_cardinality, 4)
  assert_eq(trace.nodes, 4)
  assert_eq(trace.depth, 2)
  assert_eq(query.result_upper_bound(catalog, universe), 5)
}

///|
test "snapshots advance by patches and round trip through checked envelopes" {
  let initial = @moonbit-roaring.RoaringSnapshot::new(
    @moonbit-roaring.RoaringBitmap::from_array([1, 2, 4]).unwrap(),
  )
  let target = @moonbit-roaring.RoaringSnapshot::at(
    8,
    @moonbit-roaring.RoaringBitmap::from_array([2, 3, 4, 9]).unwrap(),
  ).unwrap()
  let patch = initial.diff_to(target)
  let advanced = initial.advance(patch).unwrap()
  assert_eq(advanced.generation(), 1)
  assert_eq(advanced.bitmap().to_array(), [2, 3, 4, 9])
  let envelope = target.envelope(RunWords).unwrap()
  assert_eq(envelope.generation(), 8)
  let restored = envelope.decode().unwrap()
  assert_eq(restored.generation(), 8)
  assert_eq(restored.bitmap().to_array(), [2, 3, 4, 9])
  assert_true(
    @moonbit-roaring.RoaringSnapshot::at(
      -1,
      @moonbit-roaring.RoaringBitmap::new(),
    )
    is Err(InvalidGeneration(-1)),
  )
}

///|
test "patch envelopes enforce generation ordering and checked reconstruction" {
  let base = @moonbit-roaring.RoaringSnapshot::at(
    3,
    @moonbit-roaring.RoaringBitmap::from_array([1, 2, 5]).unwrap(),
  ).unwrap()
  let target = @moonbit-roaring.RoaringSnapshot::at(
    7,
    @moonbit-roaring.RoaringBitmap::from_array([2, 3, 5, 8]).unwrap(),
  ).unwrap()
  let envelope = base.patch_envelope(target, PlainWords).unwrap()
  assert_eq(envelope.base_generation(), 3)
  assert_eq(envelope.target_generation(), 7)
  let applied = base.apply_patch_envelope(envelope).unwrap()
  assert_eq(applied.generation(), 7)
  assert_eq(applied.bitmap().to_array(), [2, 3, 5, 8])
  let stale = @moonbit-roaring.RoaringSnapshot::at(4, base.bitmap()).unwrap()
  assert_true(
    stale.apply_patch_envelope(envelope) is Err(StaleGeneration(4, 3)),
  )
}

///|
test "batch analysis reports exact aggregate and occurrence facts" {
  let a = @moonbit-roaring.RoaringBitmap::from_array([1, 2, 4]).unwrap()
  let b = @moonbit-roaring.RoaringBitmap::from_array([2, 3, 4]).unwrap()
  let c = @moonbit-roaring.RoaringBitmap::from_array([4, 5]).unwrap()
  let report = @moonbit-roaring.analyze_batch([a, b, c])
  assert_eq(report.operand_count, 3)
  assert_eq(report.total_cardinality, 8)
  assert_eq(report.union_cardinality, 5)
  assert_eq(report.intersection_cardinality, 1)
  assert_eq(report.duplicate_occurrences, 3)
  assert_eq(@moonbit-roaring.values_at_least([a, b, c], 2).to_array(), [2, 4])
  assert_eq(@moonbit-roaring.values_in_exactly_one([a, b, c]).to_array(), [
    1, 3, 5,
  ])
  assert_eq(@moonbit-roaring.overlap_with_others([a, b, c]), [2, 2, 1])
}

///|
test "comparison reports precision recall and universe-restricted equality" {
  let actual = @moonbit-roaring.RoaringBitmap::from_array([1, 2, 4, 7]).unwrap()
  let expected = @moonbit-roaring.RoaringBitmap::from_array([2, 3, 4, 8]).unwrap()
  let report = @moonbit-roaring.compare_bitmaps(actual, expected)
  assert_true(report.relation is Overlap)
  assert_eq(report.common_cardinality, 2)
  assert_eq(report.left_only_cardinality, 2)
  assert_eq(report.right_only_cardinality, 2)
  assert_eq(report.union_cardinality, 6)
  assert_eq(@moonbit-roaring.precision_parts(actual, expected), (2, 4))
  assert_eq(@moonbit-roaring.recall_parts(actual, expected), (2, 4))
  assert_eq(@moonbit-roaring.f1_parts(actual, expected), (4, 8))
  assert_true(
    @moonbit-roaring.equal_within(
      actual,
      expected,
      @moonbit-roaring.RoaringBitmap::from_array([2, 4]).unwrap(),
    ),
  )
}

///|
test "snapshot and patch error paths retain the original immutable state" {
  let base = @moonbit-roaring.RoaringSnapshot::at(
    1,
    @moonbit-roaring.RoaringBitmap::from_array([1, 2, 3]).unwrap(),
  ).unwrap()
  let target = @moonbit-roaring.RoaringSnapshot::at(
    2,
    @moonbit-roaring.RoaringBitmap::from_array([2, 4]).unwrap(),
  ).unwrap()
  let envelope = base.patch_envelope(target, RunWords).unwrap()
  let wrong = @moonbit-roaring.RoaringSnapshot::at(0, base.bitmap()).unwrap()
  assert_true(
    wrong.apply_patch_envelope(envelope) is Err(StaleGeneration(0, 1)),
  )
  assert_eq(base.bitmap().to_array(), [1, 2, 3])
  let frame = target.envelope(PlainWords).unwrap()
  let restored = frame.decode().unwrap()
  assert_eq(restored.bitmap().to_array(), [2, 4])
  assert_true(
    @moonbit-roaring.RoaringSnapshot::at(-99, base.bitmap())
    is Err(InvalidGeneration(-99)),
  )
}

///|
test "batch analysis handles empty and duplicate-heavy operand lists" {
  let empty = @moonbit-roaring.RoaringBitmap::new()
  let repeated = @moonbit-roaring.RoaringBitmap::from_array([1, 2, 3]).unwrap()
  let report = @moonbit-roaring.analyze_batch([empty, repeated, repeated])
  assert_eq(report.operand_count, 3)
  assert_eq(report.empty_operands, 1)
  assert_eq(report.total_cardinality, 6)
  assert_eq(report.union_cardinality, 3)
  assert_eq(report.intersection_cardinality, 0)
  assert_eq(report.duplicate_occurrences, 3)
  assert_eq(
    @moonbit-roaring.values_at_least([empty, repeated, repeated], 2).to_array(),
    [1, 2, 3],
  )
  assert_eq(@moonbit-roaring.values_at_least([empty, repeated], 3).to_array(), [])
  assert_eq(
    @moonbit-roaring.values_in_exactly_one([empty, repeated, repeated]).to_array(),
    [],
  )
  assert_eq(@moonbit-roaring.overlap_with_others([empty, repeated, repeated]), [
    0, 3, 3,
  ])
}

///|
test "journal split checkpoint frames and patch inversion compose correctly" {
  let checkpoint = @moonbit-roaring.RoaringBitmap::from_array([1, 5, 9]).unwrap()
  let log = @moonbit-roaring.RoaringOperationLog::new(checkpoint).append_all([
    Add(2),
    Remove(5),
    AddRange(10, 13),
    RemoveAll([1, 11]),
  ])
  let (prefix, suffix) = log.split_at(2).unwrap()
  let prefix_state = prefix.replay().unwrap()
  let final_state = suffix.replay().unwrap()
  assert_eq(prefix_state.to_array(), [1, 2, 9])
  assert_eq(final_state.to_array(), [2, 9, 10, 12])
  let frame = suffix.checkpoint_frame(RunWords).unwrap()
  assert_eq(frame.decode().unwrap().to_array(), final_state.to_array())
  let patch = prefix_state.diff_to(final_state)
  assert_eq(
    patch.invert().apply(final_state).to_array(),
    prefix_state.to_array(),
  )
  assert_eq(patch.touched().to_array(), [1, 10, 12])
}

///|
test "query upper bounds remain safe for negation conjunction and threshold" {
  let universe = @moonbit-roaring.RoaringBitmap::from_range(0, 10).unwrap()
  let catalog = @moonbit-roaring.BitmapCatalog::new()
    .upsert(1, @moonbit-roaring.RoaringBitmap::from_array([1, 2, 3]).unwrap())
    .upsert(2, @moonbit-roaring.RoaringBitmap::from_array([2, 3]).unwrap())
  let negative = @moonbit-roaring.CatalogQuery::Not(
    @moonbit-roaring.CatalogQuery::Key(1),
  )
  let all = @moonbit-roaring.CatalogQuery::All([
    @moonbit-roaring.CatalogQuery::Key(1),
    @moonbit-roaring.CatalogQuery::Key(2),
  ])
  let impossible = @moonbit-roaring.CatalogQuery::AtLeast(3, [
    @moonbit-roaring.CatalogQuery::Key(1),
    @moonbit-roaring.CatalogQuery::Key(2),
  ])
  assert_eq(negative.result_upper_bound(catalog, universe), 10)
  assert_eq(all.result_upper_bound(catalog, universe), 2)
  assert_eq(impossible.result_upper_bound(catalog, universe), 0)
  assert_true(
    catalog.execute_with_trace(negative, universe).result_cardinality <= 10,
  )
  assert_true(catalog.execute_with_trace(all, universe).result_cardinality <= 2)
  assert_true(
    catalog.execute_with_trace(impossible, universe).result.is_empty(),
  )
}

///|
test "comparison analysis and sampling agree on a shared derived result" {
  let left = @moonbit-roaring.RoaringBitmap::from_array([1, 2, 3, 10, 11]).unwrap()
  let right = @moonbit-roaring.RoaringBitmap::from_array([2, 3, 4, 11, 12]).unwrap()
  let common = left.intersection(right)
  let comparison = @moonbit-roaring.compare_bitmaps(left, right)
  let batch = @moonbit-roaring.analyze_batch([left, right, common])
  assert_eq(common.to_array(), [2, 3, 11])
  assert_eq(comparison.common_cardinality, common.cardinality())
  assert_eq(batch.intersection_cardinality, 3)
  assert_eq(common.sample_evenly(2), [2, 3])
  assert_eq(common.sample_stride(2), [2, 11])
  assert_true(common.validate() is Ok(_))
  assert_eq(common.cardinality(), 3)
}

///|
test "operation journals preserve order batches and malformed boundaries" {
  let checkpoint = @moonbit-roaring.RoaringBitmap::from_array([1, 4, 8]).unwrap()
  let log = @moonbit-roaring.RoaringOperationLog::new(checkpoint).append_all([
    Add(2),
    AddRange(10, 12),
    RemoveAll([4, 99]),
    AddAll([3, 5]),
    Remove(8),
  ])
  let words = log.encode_words()
  let decoded = @moonbit-roaring.decode_operation_log(checkpoint, words).unwrap()
  assert_eq(decoded.replay().unwrap().to_array(), [1, 2, 3, 5, 10, 11])
  assert_true(
    @moonbit-roaring.decode_operation_log(checkpoint, []) is Err(MissingHeader),
  )
  assert_true(
    @moonbit-roaring.decode_operation_log(checkpoint, [1, 1, 9])
    is Err(InvalidTag(9)),
  )
  assert_true(
    @moonbit-roaring.decode_operation_log(checkpoint, [1, 1, 5, 3, 1])
    is Err(InvalidBatchCount(3)),
  )
}

///|
test "journal history supports prefix replay split and cardinality audit" {
  let checkpoint = @moonbit-roaring.RoaringBitmap::from_array([1, 4]).unwrap()
  let log = @moonbit-roaring.RoaringOperationLog::new(checkpoint).append_all([
    Add(2),
    Remove(4),
    AddRange(6, 8),
  ])
  assert_true(log.operation_at(-1) is Err(InvalidIndex(-1, 3)))
  assert_true(log.operation_at(3) is Err(InvalidIndex(3, 3)))
  assert_eq(log.replay_prefix(0).unwrap().to_array(), [1, 4])
  assert_eq(log.replay_prefix(2).unwrap().to_array(), [1, 2])
  assert_eq(log.cardinality_history().unwrap(), [2, 3, 2, 4])
  let (prefix, suffix) = log.split_at(2).unwrap()
  assert_eq(prefix.replay().unwrap().to_array(), [1, 2])
  assert_eq(suffix.replay().unwrap().to_array(), [1, 2, 6, 7])
}
