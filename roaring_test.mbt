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
