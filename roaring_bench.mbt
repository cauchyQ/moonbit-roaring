///|
/// Reproducible workload fixtures used by `moon bench --release`.
fn benchmark_left() -> RoaringBitmap {
  let values : Array[Int] = []
  for value in 0..<6_000 {
    values.push(value * 3)
  }
  RoaringBitmap::from_array(values).unwrap()
}

///|
fn benchmark_right() -> RoaringBitmap {
  let values : Array[Int] = []
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
}
