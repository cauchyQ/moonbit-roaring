///|
/// Keep values satisfying `predicate` and preserve normalized ordering.
pub fn RoaringBitmap::filter(
  self : RoaringBitmap,
  predicate : (Int) -> Bool,
) -> RoaringBitmap {
  from_sorted(self.to_array().filter(predicate))
}

///|
/// Map values and normalize the mapped result. A negative mapped value is
/// rejected instead of silently dropping it.
pub fn RoaringBitmap::map_values(
  self : RoaringBitmap,
  mapper : (Int) -> Int,
) -> Result[RoaringBitmap, RoaringError] {
  let values : Array[Int] = []
  for value in self.to_array() {
    let mapped = mapper(value)
    if mapped < 0 {
      return Err(NegativeValue(mapped))
    }
    values.push(mapped)
  }
  RoaringBitmap::from_array(values)
}

///|
/// Split values into matching and non-matching bitmaps.
pub fn RoaringBitmap::partition(
  self : RoaringBitmap,
  predicate : (Int) -> Bool,
) -> (RoaringBitmap, RoaringBitmap) {
  let yes : Array[Int] = []
  let no : Array[Int] = []
  for value in self.to_array() {
    if predicate(value) {
      yes.push(value)
    } else {
      no.push(value)
    }
  }
  (from_sorted(yes), from_sorted(no))
}

///|
/// Keep the first `count` values in ascending order. Negative counts are empty.
pub fn RoaringBitmap::take(self : RoaringBitmap, count : Int) -> RoaringBitmap {
  if count <= 0 {
    return RoaringBitmap::new()
  }
  let output : Array[Int] = []
  let values = self.to_array()
  for index in 0..<values.length() {
    if index < count {
      output.push(values[index])
    }
  }
  from_sorted(output)
}

///|
/// Discard the first `count` values in ascending order. Negative counts are a no-op.
pub fn RoaringBitmap::drop(self : RoaringBitmap, count : Int) -> RoaringBitmap {
  if count <= 0 {
    return self
  }
  let output : Array[Int] = []
  let values = self.to_array()
  for index in 0..<values.length() {
    if index >= count {
      output.push(values[index])
    }
  }
  from_sorted(output)
}

///|
/// Select values whose zero-based positions belong to `[start, end)`.
pub fn RoaringBitmap::slice_positions(
  self : RoaringBitmap,
  start : Int,
  end : Int,
) -> Result[RoaringBitmap, RoaringError] {
  if start < 0 || end < start {
    return Err(InvalidRange(start, end))
  }
  let output : Array[Int] = []
  let values = self.to_array()
  for index in 0..<values.length() {
    if start <= index && index < end {
      output.push(values[index])
    }
  }
  Ok(from_sorted(output))
}

///|
/// Shift every value by `offset`, rejecting shifts that leave the supported
/// non-negative `Int` domain.
pub fn RoaringBitmap::shift(
  self : RoaringBitmap,
  offset : Int,
) -> Result[RoaringBitmap, RoaringError] {
  let values : Array[Int] = []
  for value in self.to_array() {
    if offset < 0 && value < -offset {
      return Err(NegativeValue(value + offset))
    }
    if offset > 0 && value > 2_147_483_647 - offset {
      return Err(RangeEndpointOverflow(value))
    }
    values.push(value + offset)
  }
  RoaringBitmap::from_array(values)
}
