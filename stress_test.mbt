///|
fn generated_values(
  seed : Int,
  multiplier : Int,
  increment : Int,
) -> Array[Int] {
  let values : Array[Int] = []
  for index in 0..<96 {
    values.push(
      (seed * multiplier + index * increment + index * index) % 180_000,
    )
  }
  values
}

///|
fn normalized_oracle(values : Array[Int]) -> Array[Int] {
  let sorted = values.copy()
  sorted.sort()
  let output : Array[Int] = []
  for value in sorted {
    if output.length() == 0 || output[output.length() - 1] != value {
      output.push(value)
    }
  }
  output
}

///|
fn oracle_contains(values : Array[Int], value : Int) -> Bool {
  normalized_oracle(values).contains(value)
}

///|
fn oracle_rank(values : Array[Int], value : Int) -> Int {
  normalized_oracle(values).filter(item => item <= value).length()
}

///|
test "generated membership rank select and codec cases remain consistent" {
  for seed in 0..<64 {
    let raw = generated_values(seed, 337, 997)
    let bitmap = RoaringBitmap::from_array(raw).unwrap()
    let oracle = normalized_oracle(raw)
    assert_eq(bitmap.to_array(), oracle)
    assert_eq(bitmap.cardinality(), oracle.length())
    for probe in [0, 1, 511, 65_535, 65_536, 131_071, 179_999] {
      assert_eq(bitmap.contains(probe), oracle_contains(raw, probe))
      assert_eq(bitmap.rank(probe), oracle_rank(raw, probe))
    }
    for index in 0..<oracle.length() {
      assert_eq(bitmap.select(index), Some(oracle[index]))
    }
    assert_eq(bitmap.select(oracle.length()), None)
    let plain = bitmap.encode_words()
    let run = bitmap.encode_run_words().unwrap()
    assert_eq(decode_words(plain).unwrap().to_array(), oracle)
    assert_eq(decode_run_words(run).unwrap().to_array(), oracle)
  }
}

///|
test "generated algebra agrees with explicit value membership oracle" {
  for seed in 0..<64 {
    let left_raw = generated_values(seed, 149, 613)
    let right_raw = generated_values(seed + 17, 271, 431)
    let left = RoaringBitmap::from_array(left_raw).unwrap()
    let right = RoaringBitmap::from_array(right_raw).unwrap()
    let left_values = normalized_oracle(left_raw)
    let right_values = normalized_oracle(right_raw)
    let union_expected : Array[Int] = []
    let intersection_expected : Array[Int] = []
    let difference_expected : Array[Int] = []
    let xor_expected : Array[Int] = []
    for value in 0..<180_000 {
      let in_left = left_values.contains(value)
      let in_right = right_values.contains(value)
      if in_left || in_right {
        union_expected.push(value)
      }
      if in_left && in_right {
        intersection_expected.push(value)
      }
      if in_left && !in_right {
        difference_expected.push(value)
      }
      if in_left != in_right {
        xor_expected.push(value)
      }
    }
    assert_eq(left.union(right).to_array(), union_expected)
    assert_eq(left.intersection(right).to_array(), intersection_expected)
    assert_eq(left.difference(right).to_array(), difference_expected)
    assert_eq(left.xor(right).to_array(), xor_expected)
    assert_true(left.union(right).validate() is Ok(_))
    assert_true(left.intersection(right).validate() is Ok(_))
    assert_true(left.difference(right).validate() is Ok(_))
    assert_true(left.xor(right).validate() is Ok(_))
  }
}

///|
test "generated malformed codecs and journals fail without producing state" {
  let checkpoint = RoaringBitmap::from_array([1, 2, 3]).unwrap()
  for tag in -2..<12 {
    if tag != 1 && tag != 3 {
      assert_true(decode_auto([tag, 0]) is Err(_))
    }
    if tag < 1 || tag > 6 {
      assert_true(decode_operation_log(checkpoint, [1, 1, tag]) is Err(_))
    }
  }
  for count in -3..<0 {
    assert_true(decode_operation_log(checkpoint, [1, 1, 5, count]) is Err(_))
  }
}
