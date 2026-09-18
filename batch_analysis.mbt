///|
/// Aggregate facts about a batch of bitmap operands.
pub(all) struct BitmapBatchReport {
  operand_count : Int
  total_cardinality : Int
  union_cardinality : Int
  intersection_cardinality : Int
  duplicate_occurrences : Int
  empty_operands : Int
}

///|
/// Analyze a batch using exact set algebra. Empty input has empty union and
/// intersection by the library's documented aggregate identity.
pub fn analyze_batch(bitmaps : Array[RoaringBitmap]) -> BitmapBatchReport {
  let mut total = 0
  let mut empty = 0
  for bitmap in bitmaps {
    total += bitmap.cardinality()
    if bitmap.is_empty() {
      empty += 1
    }
  }
  let union = union_all(bitmaps)
  let intersection = intersection_all(bitmaps)
  let union_cardinality = union.cardinality()
  {
    operand_count: bitmaps.length(),
    total_cardinality: total,
    union_cardinality,
    intersection_cardinality: intersection.cardinality(),
    duplicate_occurrences: total - union_cardinality,
    empty_operands: empty,
  }
}

///|
/// Return the values that appear in at least `threshold` operands.
/// Threshold zero returns the union because no external universe is supplied.
pub fn values_at_least(
  bitmaps : Array[RoaringBitmap],
  threshold : Int,
) -> RoaringBitmap {
  if threshold <= 0 {
    return union_all(bitmaps)
  }
  if threshold > bitmaps.length() {
    return RoaringBitmap::new()
  }
  let values : Array[Int] = []
  for bitmap in bitmaps {
    for value in bitmap.to_array() {
      values.push(value)
    }
  }
  values.sort()
  let output : Array[Int] = []
  let mut index = 0
  while index < values.length() {
    let value = values[index]
    let mut count = 0
    while index < values.length() && values[index] == value {
      count += 1
      index += 1
    }
    if count >= threshold {
      output.push(value)
    }
  }
  from_sorted(output)
}

///|
/// Return values present in exactly one operand.
pub fn values_in_exactly_one(bitmaps : Array[RoaringBitmap]) -> RoaringBitmap {
  let values : Array[Int] = []
  for bitmap in bitmaps {
    for value in bitmap.to_array() {
      values.push(value)
    }
  }
  values.sort()
  let output : Array[Int] = []
  let mut index = 0
  while index < values.length() {
    let value = values[index]
    let mut count = 0
    while index < values.length() && values[index] == value {
      count += 1
      index += 1
    }
    if count == 1 {
      output.push(value)
    }
  }
  from_sorted(output)
}

///|
/// Return each operand's overlap count with the union of all other operands.
pub fn overlap_with_others(bitmaps : Array[RoaringBitmap]) -> Array[Int] {
  let output : Array[Int] = []
  for index in 0..<bitmaps.length() {
    let others : Array[RoaringBitmap] = []
    for other_index in 0..<bitmaps.length() {
      if index != other_index {
        others.push(bitmaps[other_index])
      }
    }
    output.push(bitmaps[index].intersection(union_all(others)).cardinality())
  }
  output
}
