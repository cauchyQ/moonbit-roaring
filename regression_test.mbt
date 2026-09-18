///|
test "catalog traced evaluation distinguishes missing labels from empty results" {
  let universe = RoaringBitmap::from_array([1, 2, 3, 4]).unwrap()
  let catalog = BitmapCatalog::new()
    .upsert(10, RoaringBitmap::from_array([1, 2]).unwrap())
    .upsert(20, RoaringBitmap::new())
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
  let universe = RoaringBitmap::from_array([1, 2, 3]).unwrap()
  let catalog = BitmapCatalog::new()
  assert_true(catalog.evaluate(Any([]), universe).is_empty())
  assert_eq(catalog.evaluate(All([]), universe).to_array(), [1, 2, 3])
  assert_eq(catalog.evaluate(AtLeast(0, []), universe).to_array(), [1, 2, 3])
  assert_true(catalog.evaluate(AtLeast(1, []), universe).is_empty())
}

///|
test "operation log batch audit and pending patch preserve checkpoint semantics" {
  let checkpoint = RoaringBitmap::from_array([1, 3, 5]).unwrap()
  let log = RoaringOperationLog::new(checkpoint).append_all([
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
  let sparse = RoaringBitmap::from_array([1, 9, 17, 90_000]).unwrap()
  let plain = sparse.frame(PlainWords).unwrap()
  let runs = sparse.frame(RunWords).unwrap()
  assert_eq(plain.decode().unwrap().to_array(), sparse.to_array())
  assert_eq(runs.decode().unwrap().to_array(), sparse.to_array())
  let modified = plain.with_payload([1, 4, 1, 9, 17, 90_001])
  assert_true(modified.decode() is Err(ChecksumMismatch(_, _)))
}

///|
test "transform positional operations respect empty and out of range requests" {
  let bitmap = RoaringBitmap::from_array([10, 20, 30]).unwrap()
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
  let empty = RoaringBitmap::new()
  assert_eq(empty.profile().span, 0)
  assert_eq(empty.density_parts(), (0, 0))
  assert_eq(empty.sample_evenly(4), [])
  assert_eq(empty.sample_stride(1), [])
  assert_true(empty.quantile(0, 1) is Ok(None))
  let bitmap = RoaringBitmap::from_array([2, 4, 6, 8]).unwrap()
  assert_true(bitmap.quantile(0, 3) is Ok(Some(2)))
  assert_true(bitmap.quantile(3, 3) is Ok(Some(8)))
  assert_true(bitmap.quantile(1, 0) is Err(InvalidRange(1, 0)))
}

///|
test "plan description remains stable across binary and unary nodes" {
  let source = BitmapPlan::Source(RoaringBitmap::from_array([1, 2, 3]).unwrap())
  let plan = BitmapPlan::Drop(BitmapPlan::Take(source, 2), 1)
  assert_eq(plan.evaluate().to_array(), [2])
  assert_eq(plan.describe(), "drop(1,take(2,source(3)))")
  let stats = plan.stats()
  assert_eq(stats.nodes, 3)
  assert_eq(stats.depth, 3)
  assert_eq(stats.sources, 1)
}

///|
test "range APIs agree with rank select and cursor traversal" {
  let bitmap = RoaringBitmap::from_ranges([
    { start: 0, end: 3 },
    { start: 10, end: 14 },
    { start: 65_535, end: 65_538 },
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
  let base = RoaringBitmap::from_array([1, 3, 5, 7]).unwrap()
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
    .add_ranges([{ start: 10, end: 13 }, { start: 12, end: 15 }])
    .unwrap()
  assert_eq(range_bulk.to_array(), [1, 3, 5, 7, 10, 11, 12, 13, 14])
  assert_eq(
    range_bulk.remove_ranges([{ start: 3, end: 13 }]).unwrap().to_array(),
    [1, 13, 14],
  )
}

///|
test "codec conversions retain canonical forms for sparse dense and run data" {
  let sparse = RoaringBitmap::from_array([1, 99, 70_000]).unwrap()
  let dense = RoaringBitmap::new().add_range(0, 5_000).unwrap()
  let runs = RoaringBitmap::from_ranges([
    { start: 5, end: 45 },
    { start: 100, end: 120 },
  ]).unwrap()
  for bitmap in [sparse, dense, runs] {
    let plain = bitmap.encode(PlainWords).unwrap()
    let run = bitmap.encode(RunWords).unwrap()
    assert_eq(decode_auto(plain).unwrap().to_array(), bitmap.to_array())
    assert_eq(decode_auto(run).unwrap().to_array(), bitmap.to_array())
    assert_eq(transcode(plain, PlainWords, RunWords).unwrap(), run)
    assert_eq(
      transcode(run, RunWords, PlainWords).unwrap(),
      bitmap.encode_words(),
    )
  }
}

///|
test "mixed container algebra obeys distributive and cancellation laws" {
  let sparse = RoaringBitmap::from_array([1, 7, 65_537, 130_000]).unwrap()
  let dense = RoaringBitmap::new().add_range(0, 5_000).unwrap()
  let runs = RoaringBitmap::from_ranges([
    { start: 3_000, end: 3_100 },
    { start: 65_530, end: 65_540 },
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
  let original = RoaringBitmap::from_array([2, 4, 6]).unwrap()
  assert_true(original.add_all([8, -1]) is Err(NegativeValue(-1)))
  assert_true(original.add_range(-1, 4) is Err(InvalidRange(-1, 4)))
  assert_true(original.add_range(4, 3) is Err(InvalidRange(4, 3)))
  assert_true(original.add_range(0, 1_000_001) is Err(RangeTooLarge(1_000_001)))
  assert_true(
    original.remove_ranges([{ start: 9, end: 3 }]) is Err(InvalidRange(9, 3)),
  )
  assert_eq(original.to_array(), [2, 4, 6])
  let builder = RoaringBuilder::new()
  assert_true(builder.push_all([1, 2]) is Ok(_))
  assert_true(builder.push_all([3, -7, 5]) is Err(NegativeValue(-7)))
  assert_eq(builder.staged_len(), 2)
  assert_eq(builder.finish().to_array(), [1, 2])
}

///|
test "empty and singleton bitmaps retain all public invariants" {
  let empty = RoaringBitmap::new()
  assert_true(empty.validate() is Ok(_))
  assert_eq(empty.minimum(), None)
  assert_eq(empty.maximum(), None)
  assert_eq(empty.select(0), None)
  assert_eq(empty.rank(0), 0)
  assert_true(empty.is_subset_of(RoaringBitmap::new()))
  let singleton = RoaringBitmap::from_array([2_147_483_647]).unwrap()
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
  let universe = RoaringBitmap::from_range(0, 20).unwrap()
  let catalog = BitmapCatalog::new()
    .upsert(
      1,
      RoaringBitmap::from_ranges([{ start: 0, end: 8 }, { start: 12, end: 16 }]).unwrap(),
    )
    .upsert(
      2,
      RoaringBitmap::from_ranges([{ start: 4, end: 12 }, { start: 16, end: 20 }]).unwrap(),
    )
  let selected = catalog.evaluate(AtLeast(2, [Key(1), Key(2)]), universe)
  assert_eq(selected.to_array(), [4, 5, 6, 7])
  let plan = BitmapPlan::Union(
    BitmapPlan::Source(selected),
    BitmapPlan::Source(RoaringBitmap::from_array([18]).unwrap()),
  )
  let planned = plan.evaluate()
  let log = RoaringOperationLog::new(planned).append_all([Remove(5), Add(19)])
  let updated = log.replay().unwrap()
  let patch = planned.diff_to(updated)
  assert_eq(patch.apply(planned).to_array(), [4, 6, 7, 18, 19])
  let encoded = updated.frame(RunWords).unwrap()
  assert_eq(encoded.decode().unwrap().to_array(), updated.to_array())
  assert_true(updated.validate() is Ok(_))
}

///|
test "catalog query metadata preserves repeated references and nesting depth" {
  let query = CatalogQuery::Any([
    CatalogQuery::Key(1),
    CatalogQuery::Not(
      CatalogQuery::All([
        CatalogQuery::Key(2),
        CatalogQuery::AtLeast(1, [CatalogQuery::Key(1), CatalogQuery::Key(3)]),
      ]),
    ),
  ])
  let keys = query.referenced_keys()
  assert_eq(keys, [1, 2, 1, 3])
  let stats = query.stats()
  assert_eq(stats.nodes, 8)
  assert_eq(stats.depth, 5)
  assert_eq(stats.key_references, 4)
  let universe = RoaringBitmap::from_array([1, 2, 3]).unwrap()
  let catalog = BitmapCatalog::new()
    .upsert(1, RoaringBitmap::from_array([1]).unwrap())
    .upsert(2, RoaringBitmap::from_array([2]).unwrap())
  let traced = catalog.evaluate_traced(query, universe)
  assert_eq(traced.missing_keys, [3])
  assert_eq(traced.bitmap.to_array(), [1, 2, 3])
}
