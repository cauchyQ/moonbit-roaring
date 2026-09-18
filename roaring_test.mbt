///|
test "array and run containers preserve normalized values" {
  let bitmap = RoaringBitmap::from_array([7, 2, 3, 4, 4, 70_000]).unwrap()
  assert_eq(bitmap.to_array(), [2, 3, 4, 7, 70_000])
  assert_eq(bitmap.cardinality(), 5)
}

///|
test "set algebra matches integer-set semantics" {
  let left = RoaringBitmap::from_array([1, 2, 3, 70_000]).unwrap()
  let right = RoaringBitmap::from_array([3, 4, 70_000, 80_000]).unwrap()
  assert_eq(left.union(right).to_array(), [1, 2, 3, 4, 70_000, 80_000])
  assert_eq(left.intersection(right).to_array(), [3, 70_000])
  assert_eq(left.difference(right).to_array(), [1, 2])
  assert_eq(left.xor(right).to_array(), [1, 2, 4, 80_000])
}

///|
test "dense blocks use bitmap storage without changing rank or select" {
  let bitmap = RoaringBitmap::new().add_range(0, 5_000).unwrap()
  assert_eq(bitmap.cardinality(), 5_000)
  assert_eq(bitmap.rank(37), 38)
  assert_eq(bitmap.select(4_999), Some(4_999))
  assert_eq(bitmap.select(5_000), None)
}

///|
test "dense bitmap operations use word algebra and downshift sparse results" {
  let left = RoaringBitmap::new().add_range(0, 5_000).unwrap()
  let right = RoaringBitmap::new().add_range(4_000, 9_000).unwrap()
  let overlap = left.intersection(right)
  assert_eq(overlap.cardinality(), 1_000)
  assert_eq(overlap.stats().bitmap_blocks, 0)
  assert_eq(left.union(right).cardinality(), 9_000)
  assert_eq(left.difference(right).cardinality(), 4_000)
  assert_eq(left.xor(right).cardinality(), 8_000)
}

///|
test "block diagnostics expose selected representations without internals" {
  let values : Array[Int] = [1]
  for value in 70_000..<70_006 {
    values.push(value)
  }
  for value in 131_072..<136_072 {
    values.push(value)
  }
  let blocks = RoaringBitmap::from_array(values).unwrap().block_stats()
  assert_eq(blocks.length(), 3)
  assert_eq(blocks[0].key, 0)
  assert_true(blocks[0].kind is Array)
  assert_true(blocks[1].kind is Run)
  assert_eq(blocks[1].cardinality, 6)
  assert_true(blocks[2].kind is Bitmap)
}

///|
test "non-negative boundary and removal are checked" {
  let bitmap = RoaringBitmap::new().add(2_147_483_647).unwrap()
  assert_true(bitmap.contains(2_147_483_647))
  assert_eq(bitmap.remove(2_147_483_647).cardinality(), 0)
  assert_true(RoaringBitmap::new().add(-1) is Err(NegativeValue(-1)))
}

///|
test "metadata and relational queries preserve set semantics" {
  let sparse = RoaringBitmap::from_array([4, 7, 9]).unwrap()
  let dense = RoaringBitmap::new().add_range(0, 5_000).unwrap()
  assert_eq(sparse.minimum(), Some(4))
  assert_eq(sparse.maximum(), Some(9))
  assert_true(sparse.intersects(dense))
  assert_true(sparse.difference(dense).is_subset_of(sparse))
  assert_eq(dense.stats().bitmap_blocks, 1)
}

///|
test "container-aware point and range queries cross block boundaries" {
  let bitmap = RoaringBitmap::from_array([1, 2, 3, 65_535, 65_536, 65_538]).unwrap()
  assert_true(bitmap.contains(65_536))
  assert_true(!bitmap.contains(65_537))
  assert_eq(bitmap.rank(65_535), 4)
  assert_eq(bitmap.rank(65_536), 5)
  assert_eq(bitmap.select(4), Some(65_536))
  assert_true(bitmap.contains_range(1, 4) is Ok(true))
  assert_true(bitmap.contains_range(65_535, 65_538) is Ok(false))
  assert_eq(bitmap.count_in_range(65_535, 65_538).unwrap(), 2)
  assert_eq(bitmap.next_at_or_after(4), Some(65_535))
  assert_eq(bitmap.previous_at_or_before(65_537), Some(65_536))
}

///|
test "batch range cursor and codec APIs are deterministic" {
  let bitmap = RoaringBitmap::from_range(2, 6).unwrap().add_all([8, 9]).unwrap()
  let trimmed = bitmap.remove_range(3, 5).unwrap().remove_all([9]).unwrap()
  assert_eq(trimmed.to_array(), [2, 5, 8])
  assert_true(trimmed.count_in_range(2, 8) is Ok(2))
  let (first, cursor) = trimmed.cursor().next()
  assert_eq(cursor.remaining(), 2)
  let (second, cursor) = cursor.next()
  let (third, cursor) = cursor.next()
  assert_eq(first, Some(2))
  assert_eq(second, Some(5))
  assert_eq(third, Some(8))
  assert_eq(cursor.remaining(), 0)
  assert_eq(decode_words(trimmed.encode_words()).unwrap().to_array(), [2, 5, 8])
}

///|
test "bulk aggregation uses the documented empty identities" {
  let first = RoaringBitmap::from_array([1, 2, 4, 70_000]).unwrap()
  let second = RoaringBitmap::from_array([2, 3, 4, 80_000]).unwrap()
  let third = RoaringBitmap::from_array([2, 4, 5]).unwrap()
  assert_eq(union_all([first, second, third]).to_array(), [
    1, 2, 3, 4, 5, 70_000, 80_000,
  ])
  assert_eq(intersection_all([first, second, third]).to_array(), [2, 4])
  assert_eq(xor_all([first, second, third]).to_array(), [
    1, 2, 3, 4, 5, 70_000, 80_000,
  ])
  assert_true(union_all([]).is_empty())
  assert_true(intersection_all([]).is_empty())
}

///|
test "codec rejects invalid version count and noncanonical input" {
  assert_true(decode_words([]) is Err(MissingHeader))
  assert_true(decode_words([2, 0]) is Err(UnsupportedVersion(2)))
  assert_true(decode_words([1, 2, 7]) is Err(InvalidPayloadLength(2, 1)))
  assert_true(decode_words([1, 2, 7, 7]) is Err(NonCanonicalPayload))
}

///|
test "run words are stable compact and reject malformed runs" {
  let bitmap = RoaringBitmap::from_ranges([
    { start: 2, end: 8 },
    { start: 70_000, end: 70_004 },
  ]).unwrap()
  let words = bitmap.encode_run_words().unwrap()
  assert_eq(words, [3, 10, 2, 2, 6, 70_000, 4])
  assert_eq(decode_run_words(words).unwrap().to_array(), bitmap.to_array())
  assert_true(decode_run_words([3, 1, 1, 2, 0]) is Err(InvalidRunLength(0)))
  assert_true(
    decode_run_words([3, 2, 1, 2, 1]) is Err(CardinalityMismatch(2, 1)),
  )
  assert_true(
    decode_run_words([3, 2, 2, 2, 1, 3, 1]) is Err(NonCanonicalPayload),
  )
  assert_true(
    decode_run_words([3, 1_000_001, 1, 0, 1_000_001])
    is Err(PayloadTooLarge(1_000_001)),
  )
}

///|
test "patches transform and reverse a bitmap without retaining base state" {
  let base = RoaringBitmap::from_array([1, 2, 3, 70_000]).unwrap()
  let target = RoaringBitmap::from_array([2, 3, 4, 80_000]).unwrap()
  let patch = base.diff_to(target)
  assert_eq(patch.added_cardinality(), 2)
  assert_eq(patch.removed_cardinality(), 2)
  assert_eq(patch.touched().to_array(), [1, 4, 70_000, 80_000])
  assert_eq(patch.apply(base).to_array(), target.to_array())
  assert_eq(patch.invert().apply(target).to_array(), base.to_array())
  assert_true(base.diff_to(base).is_empty())
}

///|
test "transforms preserve normalization and enforce integer boundaries" {
  let bitmap = RoaringBitmap::from_array([1, 2, 3, 4, 8]).unwrap()
  assert_eq(bitmap.filter(value => value % 2 == 0).to_array(), [2, 4, 8])
  assert_eq(bitmap.map_values(value => value / 2).unwrap().to_array(), [
    0, 1, 2, 4,
  ])
  let (even, odd) = bitmap.partition(value => value % 2 == 0)
  assert_eq(even.to_array(), [2, 4, 8])
  assert_eq(odd.to_array(), [1, 3])
  assert_eq(bitmap.take(3).to_array(), [1, 2, 3])
  assert_eq(bitmap.drop(3).to_array(), [4, 8])
  assert_eq(bitmap.slice_positions(1, 4).unwrap().to_array(), [2, 3, 4])
  assert_eq(bitmap.shift(10).unwrap().to_array(), [11, 12, 13, 14, 18])
  assert_true(bitmap.shift(-2) is Err(NegativeValue(-1)))
}

///|
test "operation log replays in order and compacts only after success" {
  let base = RoaringBitmap::from_array([1, 4]).unwrap()
  let log = RoaringOperationLog::new(base)
    .append(Add(2))
    .append(AddRange(5, 8))
    .append(Remove(4))
    .append(RemoveAll([6, 99]))
  assert_eq(log.len(), 4)
  assert_eq(log.replay().unwrap().to_array(), [1, 2, 5, 7])
  let compacted = log.compact().unwrap()
  assert_eq(compacted.len(), 0)
  assert_eq(compacted.replay().unwrap().to_array(), [1, 2, 5, 7])
  let invalid = log.append(Add(-1))
  assert_true(invalid.replay() is Err(NegativeValue(-1)))
}

///|
test "analytics exposes exact ratios and stable positional samples" {
  let bitmap = RoaringBitmap::from_array([2, 4, 8, 16, 32]).unwrap()
  let profile = bitmap.profile()
  assert_eq(profile.cardinality, 5)
  assert_eq(profile.minimum, Some(2))
  assert_eq(profile.maximum, Some(32))
  assert_eq(profile.span, 31)
  assert_eq(bitmap.sample_evenly(3), [2, 4, 16])
  assert_eq(bitmap.sample_evenly(99), [2, 4, 8, 16, 32])
  assert_true(bitmap.quantile(1, 2) is Ok(Some(8)))
  assert_true(bitmap.quantile(2, 1) is Err(InvalidRange(2, 1)))
  let other = RoaringBitmap::from_array([4, 8, 64]).unwrap()
  assert_eq(bitmap.jaccard_parts(other), (2, 6))
}

///|
test "range and batch APIs reject unsafe or invalid input" {
  assert_true(RoaringBitmap::from_range(4, 3) is Err(InvalidRange(4, 3)))
  assert_true(
    RoaringBitmap::from_range(0, 1_000_001) is Err(RangeTooLarge(1_000_001)),
  )
  let bitmap = RoaringBitmap::from_array([2, 4]).unwrap()
  assert_true(bitmap.remove_all([4, -1]) is Err(NegativeValue(-1)))
  let cleared = RoaringBitmap::from_array([2, 700_000])
    .unwrap()
    .remove_range(0, 1_500_000)
    .unwrap()
  assert_true(cleared.is_empty())
}

///|
test "batch range construction normalizes overlaps and protects total size" {
  let bitmap = RoaringBitmap::from_ranges([
    { start: 2, end: 5 },
    { start: 4, end: 8 },
    { start: 10, end: 12 },
  ]).unwrap()
  assert_eq(bitmap.to_array(), [2, 3, 4, 5, 6, 7, 10, 11])
  let ranges = bitmap.to_ranges().unwrap()
  assert_eq(ranges.length(), 2)
  assert_eq(ranges[0].start, 2)
  assert_eq(ranges[0].end, 8)
  assert_eq(ranges[1].start, 10)
  assert_eq(ranges[1].end, 12)
  assert_eq(bitmap.remove_ranges([{ start: 3, end: 11 }]).unwrap().to_array(), [
    2, 11,
  ])
  assert_true(
    RoaringBitmap::from_ranges([{ start: -1, end: 2 }])
    is Err(InvalidRange(-1, 2)),
  )
  assert_true(
    RoaringBitmap::from_ranges([
      { start: 0, end: 600_000 },
      { start: 700_000, end: 1_300_001 },
    ])
    is Err(RangeTooLarge(1_200_001)),
  )
  assert_true(
    RoaringBitmap::from_array([2_147_483_647]).unwrap().to_ranges()
    is Err(RangeEndpointOverflow(2_147_483_647)),
  )
}

///|
test "builder stages atomically and normalizes exactly once at finish" {
  let builder = RoaringBuilder::new()
  assert_true(builder.push_all([7, 2, 2]) is Ok(_))
  assert_true(builder.push_range(3, 6) is Ok(_))
  assert_eq(builder.staged_len(), 6)
  assert_true(builder.push_all([9, -1]) is Err(NegativeValue(-1)))
  assert_eq(builder.staged_len(), 6)
  assert_eq(builder.finish().to_array(), [2, 3, 4, 5, 7])
}

///|
test "deterministic property corpus preserves set laws and codec round trips" {
  for seed in 0..<64 {
    let left_values : Array[Int] = []
    let right_values : Array[Int] = []
    for index in 0..<48 {
      left_values.push((seed * 997 + index * 7_919) % 140_000)
      right_values.push((seed * 1_309 + index * 6_151 + 23) % 140_000)
    }
    let left = RoaringBitmap::from_array(left_values).unwrap()
    let right = RoaringBitmap::from_array(right_values).unwrap()
    assert_eq(left.union(right).to_array(), right.union(left).to_array())
    assert_eq(
      left.intersection(right).to_array(),
      right.intersection(left).to_array(),
    )
    assert_eq(left.union(left).to_array(), left.to_array())
    assert_true(left.difference(left).is_empty())
    assert_eq(
      left.intersection(right).to_array(),
      left.difference(left.difference(right)).to_array(),
    )
    assert_eq(
      decode_words(left.encode_words()).unwrap().to_array(),
      left.to_array(),
    )
  }
}
