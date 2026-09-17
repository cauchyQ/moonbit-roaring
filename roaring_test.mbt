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
