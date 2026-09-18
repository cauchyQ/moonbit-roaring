///|
fn oracle_unique(values : Array[Int]) -> Array[Int] {
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
fn oracle_union_values(left : Array[Int], right : Array[Int]) -> Array[Int] {
  oracle_unique(left + right)
}

///|
fn oracle_common_values(left : Array[Int], right : Array[Int]) -> Array[Int] {
  let right_set = oracle_unique(right)
  oracle_unique(left).filter(value => right_set.contains(value))
}

///|
fn oracle_left_values(left : Array[Int], right : Array[Int]) -> Array[Int] {
  let right_set = oracle_unique(right)
  oracle_unique(left).filter(value => !right_set.contains(value))
}

///|
test "generated differential corpus agrees with array oracle" {
  for seed in 0..<128 {
    let left : Array[Int] = []
    let right : Array[Int] = []
    for index in 0..<48 {
      left.push((seed * 109 + index * 673) % 140_000)
      right.push((seed * 251 + index * 431 + 11) % 140_000)
    }
    let a = RoaringBitmap::from_array(left).unwrap()
    let b = RoaringBitmap::from_array(right).unwrap()
    assert_eq(a.union(b).to_array(), oracle_union_values(left, right))
    assert_eq(a.intersection(b).to_array(), oracle_common_values(left, right))
    assert_eq(a.difference(b).to_array(), oracle_left_values(left, right))
    assert_eq(
      a.xor(b).to_array(),
      oracle_union_values(
        oracle_left_values(left, right),
        oracle_left_values(right, left),
      ),
    )
    assert_true(a.validate() is Ok(_))
    assert_true(b.validate() is Ok(_))
    assert_eq(decode_auto(a.encode_words()).unwrap().to_array(), a.to_array())
    assert_eq(
      decode_auto(a.encode_run_words().unwrap()).unwrap().to_array(),
      a.to_array(),
    )
  }
}
