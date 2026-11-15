///|
/// Reproducible workload fixtures used by `moon bench --release`.
fn benchmark_left() -> RoaringBitmap {
  let values : Array[Int32] = []
  for value in 0..<6_000 {
    values.push(value * 3)
  }
  RoaringBitmap::from_array(values).unwrap()
}

///|
fn benchmark_right() -> RoaringBitmap {
  let values : Array[Int32] = []
  for value in 0..<6_000 {
    values.push(value * 5 + 1)
  }
  RoaringBitmap::from_array(values).unwrap()
}

///|
test (b : @bench.T) {
  let left = benchmark_left()
  let right = benchmark_right()
  b.bench(name="union_two_dense_blocks", fn() {
    b.keep(left.union(right).cardinality())
  })
  b.bench(name="intersection_two_dense_blocks", fn() {
    b.keep(left.intersection(right).cardinality())
  })
  b.bench(name="encode_canonical_words", fn() {
    b.keep(left.encode_words().length())
  })
  b.bench(name="encode_run_words", fn() {
    b.keep(left.encode_run_words().unwrap().length())
  })
  b.bench(name="rank_dense_bitmap", fn() { b.keep(left.rank(12_345)) })
  b.bench(name="select_dense_bitmap", fn() { b.keep(left.select(4_000)) })
  b.bench(name="search_filter_intersection", fn() {
    b.keep(left.intersection(right).cardinality())
  })
  b.bench(name="permission_union_exclusion", fn() {
    b.keep(left.union(right).difference(right).cardinality())
  })
  b.bench(name="analytics_cohort_overlap", fn() {
    b.keep(left.intersection(right).cardinality())
  })
}
