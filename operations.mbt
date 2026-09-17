///|
/// Cursor for ascending traversal without exposing container internals.
pub struct RoaringCursor {
  values : Array[Int]
  index : Int
}

///|
/// A validated half-open interval used for batch range input and output.
pub(all) struct IntRange {
  start : Int
  end : Int
}

///|
/// Errors for the versioned word encoding.
pub(all) enum CodecError {
  MissingHeader
  UnsupportedVersion(Int)
  InvalidCount(Int)
  InvalidPayloadLength(Int, Int)
  InvalidValue(Int)
  NonCanonicalPayload
}

///|
/// Construct every value in the validated half-open range.
pub fn RoaringBitmap::from_range(
  start : Int,
  end : Int,
) -> Result[RoaringBitmap, RoaringError] {
  RoaringBitmap::new().add_range(start, end)
}

///|
/// Construct a bitmap from a batch of half-open ranges.
///
/// The combined materialized length is capped by the same safety limit as a
/// single range. Overlap is accepted and normalized.
pub fn RoaringBitmap::from_ranges(
  ranges : Array[IntRange],
) -> Result[RoaringBitmap, RoaringError] {
  let values : Array[Int] = []
  let mut total = 0
  for range in ranges {
    if range.start < 0 || range.end < range.start {
      return Err(InvalidRange(range.start, range.end))
    }
    let length = range.end - range.start
    if length > max_materialized_range - total {
      return Err(RangeTooLarge(total + length))
    }
    total += length
    for value in range.start..<range.end {
      values.push(value)
    }
  }
  RoaringBitmap::from_array(values)
}

///|
/// Add a batch atomically: invalid input leaves no partial result exposed.
pub fn RoaringBitmap::add_all(
  self : RoaringBitmap,
  values : Array[Int],
) -> Result[RoaringBitmap, RoaringError] {
  RoaringBitmap::from_array(self.to_array() + values)
}

///|
/// Remove every listed value; unknown values are ignored.
pub fn RoaringBitmap::remove_all(
  self : RoaringBitmap,
  values : Array[Int],
) -> Result[RoaringBitmap, RoaringError] {
  match RoaringBitmap::from_array(values) {
    Ok(removed) => Ok(self.difference(removed))
    Err(error) => Err(error)
  }
}

///|
/// Remove every value in the half-open range `[start, end)`.
pub fn RoaringBitmap::remove_range(
  self : RoaringBitmap,
  start : Int,
  end : Int,
) -> Result[RoaringBitmap, RoaringError] {
  match RoaringBitmap::from_range(start, end) {
    Ok(range) => Ok(self.difference(range))
    Err(error) => Err(error)
  }
}

///|
/// Add every value described by a validated batch of half-open ranges.
pub fn RoaringBitmap::add_ranges(
  self : RoaringBitmap,
  ranges : Array[IntRange],
) -> Result[RoaringBitmap, RoaringError] {
  match RoaringBitmap::from_ranges(ranges) {
    Ok(other) => Ok(self.union(other))
    Err(error) => Err(error)
  }
}

///|
/// Remove every value described by a validated batch of half-open ranges.
pub fn RoaringBitmap::remove_ranges(
  self : RoaringBitmap,
  ranges : Array[IntRange],
) -> Result[RoaringBitmap, RoaringError] {
  match RoaringBitmap::from_ranges(ranges) {
    Ok(other) => Ok(self.difference(other))
    Err(error) => Err(error)
  }
}

///|
/// Return a normalized interval cover of the values in this bitmap.
///
/// A bitmap containing the maximum `Int` cannot be represented as a half-open
/// interval because its end endpoint would overflow, and returns an error.
pub fn RoaringBitmap::to_ranges(
  self : RoaringBitmap,
) -> Result[Array[IntRange], RoaringError] {
  let output : Array[IntRange] = []
  let values = self.to_array()
  if values.length() == 0 {
    return Ok(output)
  }
  let mut start = values[0]
  let mut previous = start
  for index in 1..<values.length() {
    let value = values[index]
    if value != previous + 1 {
      if previous == 2_147_483_647 {
        return Err(RangeEndpointOverflow(previous))
      }
      output.push({ start, end: previous + 1 })
      start = value
    }
    previous = value
  }
  if previous == 2_147_483_647 {
    Err(RangeEndpointOverflow(previous))
  } else {
    output.push({ start, end: previous + 1 })
    Ok(output)
  }
}

///|
/// Start a stable ascending cursor.
pub fn RoaringBitmap::cursor(self : RoaringBitmap) -> RoaringCursor {
  { values: self.to_array(), index: 0 }
}

///|
/// Return the next value and a successor cursor. The original cursor is unchanged.
pub fn RoaringCursor::next(self : RoaringCursor) -> (Int?, RoaringCursor) {
  if self.index >= self.values.length() {
    (None, self)
  } else {
    (
      Some(self.values[self.index]),
      { values: self.values, index: self.index + 1 },
    )
  }
}

///|
/// Count values in the half-open range without materializing a new bitmap.
pub fn RoaringBitmap::count_in_range(
  self : RoaringBitmap,
  start : Int,
  end : Int,
) -> Result[Int, RoaringError] {
  if start < 0 || end < start {
    return Err(InvalidRange(start, end))
  }
  if start == end {
    return Ok(0)
  }
  Ok(self.rank(end - 1) - self.rank(start - 1))
}

///|
/// True only when every value in the half-open range belongs to this bitmap.
/// Unlike construction, this query never materializes the range.
pub fn RoaringBitmap::contains_range(
  self : RoaringBitmap,
  start : Int,
  end : Int,
) -> Result[Bool, RoaringError] {
  if start < 0 || end < start {
    return Err(InvalidRange(start, end))
  }
  match self.count_in_range(start, end) {
    Ok(count) => Ok(count == end - start)
    Err(error) => Err(error)
  }
}

///|
/// Return the first member greater than or equal to `value`.
pub fn RoaringBitmap::next_at_or_after(
  self : RoaringBitmap,
  value : Int,
) -> Int? {
  if self.is_empty() {
    return None
  }
  if value <= 0 {
    return self.minimum()
  }
  self.select(self.rank(value - 1))
}

///|
/// Return the last member less than or equal to `value`.
pub fn RoaringBitmap::previous_at_or_before(
  self : RoaringBitmap,
  value : Int,
) -> Int? {
  if value < 0 {
    None
  } else {
    self.select(self.rank(value) - 1)
  }
}

///| A deterministic, versioned word encoding: `[version, cardinality, values…]`.

///|
/// It is intentionally simple and platform-neutral; it is not CRoaring format.
pub fn RoaringBitmap::encode_words(self : RoaringBitmap) -> Array[Int] {
  [1, self.cardinality(), ..self.to_array()]
}

///|
/// Decode and reject malformed or non-canonical word payloads.
pub fn decode_words(words : Array[Int]) -> Result[RoaringBitmap, CodecError] {
  if words.length() == 0 {
    return Err(MissingHeader)
  }
  if words[0] != 1 {
    return Err(UnsupportedVersion(words[0]))
  }
  if words.length() < 2 || words[1] < 0 {
    return Err(InvalidCount(if words.length() < 2 { -1 } else { words[1] }))
  }
  let count = words[1]
  if words.length() != count + 2 {
    return Err(InvalidPayloadLength(count, words.length() - 2))
  }
  let values : Array[Int] = []
  for index in 2..<words.length() {
    if words[index] < 0 {
      return Err(InvalidValue(words[index]))
    }
    values.push(words[index])
  }
  let bitmap = match RoaringBitmap::from_array(values) {
    Ok(value) => value
    Err(_) => return Err(NonCanonicalPayload)
  }
  if bitmap.to_array() != values {
    Err(NonCanonicalPayload)
  } else {
    Ok(bitmap)
  }
}
