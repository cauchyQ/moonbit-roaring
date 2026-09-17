///|
/// Cursor for ascending traversal without exposing container internals.
pub struct RoaringCursor {
  bitmap : RoaringBitmap
  block_index : Int
  lows : Array[Int]
  low_index : Int
  yielded : Int
}

///|
/// A mutable staging area for bulk ingestion followed by one normalization.
pub struct RoaringBuilder {
  values : Array[Int]
}

///|
/// A validated half-open interval used for batch range input and output.
pub(all) struct IntRange {
  start : Int
  end : Int
}

///|
/// Create an empty builder.
pub fn RoaringBuilder::new() -> RoaringBuilder {
  { values: [] }
}

///|
/// Number of values staged, including duplicates that `finish` will normalize.
pub fn RoaringBuilder::staged_len(self : RoaringBuilder) -> Int {
  self.values.length()
}

///|
/// Stage one non-negative value.
pub fn RoaringBuilder::push(
  self : RoaringBuilder,
  value : Int,
) -> Result[Unit, RoaringError] {
  if value < 0 {
    return Err(NegativeValue(value))
  }
  self.values.push(value)
  Ok(())
}

///|
/// Stage a batch atomically: invalid input appends nothing.
pub fn RoaringBuilder::push_all(
  self : RoaringBuilder,
  values : Array[Int],
) -> Result[Unit, RoaringError] {
  for value in values {
    if value < 0 {
      return Err(NegativeValue(value))
    }
  }
  for value in values {
    self.values.push(value)
  }
  Ok(())
}

///|
/// Stage a range subject to the normal insertion materialization limit.
pub fn RoaringBuilder::push_range(
  self : RoaringBuilder,
  start : Int,
  end : Int,
) -> Result[Unit, RoaringError] {
  if start < 0 || end < start {
    return Err(InvalidRange(start, end))
  }
  if end - start > max_materialized_range {
    return Err(RangeTooLarge(end - start))
  }
  for value in start..<end {
    self.values.push(value)
  }
  Ok(())
}

///|
/// Normalize all staged values and return an immutable bitmap.
pub fn RoaringBuilder::finish(self : RoaringBuilder) -> RoaringBitmap {
  from_sorted(normalize(self.values))
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
  if start < 0 || end < start {
    return Err(InvalidRange(start, end))
  }
  Ok(
    from_sorted(self.to_array().filter(value => value < start || value >= end)),
  )
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
  match validate_ranges(ranges) {
    Err(error) => Err(error)
    Ok(_) =>
      Ok(
        from_sorted(
          self.to_array().filter(value => !in_any_range(value, ranges)),
        ),
      )
  }
}

///|
/// Validate interval boundaries without imposing the insertion materialization cap.
fn validate_ranges(ranges : Array[IntRange]) -> Result[Unit, RoaringError] {
  for range in ranges {
    if range.start < 0 || range.end < range.start {
      return Err(InvalidRange(range.start, range.end))
    }
  }
  Ok(())
}

///|
/// Test whether a stored value belongs to any half-open input interval.
fn in_any_range(value : Int, ranges : Array[IntRange]) -> Bool {
  for range in ranges {
    if range.start <= value && value < range.end {
      return true
    }
  }
  false
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
  { bitmap: self, block_index: 0, lows: [], low_index: 0, yielded: 0 }
}

///|
/// Return the next value and a successor cursor. The original cursor is unchanged.
pub fn RoaringCursor::next(self : RoaringCursor) -> (Int?, RoaringCursor) {
  let mut block_index = self.block_index
  let mut lows = self.lows
  let mut low_index = self.low_index
  while block_index < self.bitmap.blocks.length() && low_index >= lows.length() {
    lows = self.bitmap.blocks[block_index].container.values()
    low_index = 0
    if lows.length() == 0 {
      block_index += 1
    }
  }
  if block_index >= self.bitmap.blocks.length() {
    return (None, self)
  }
  let value = self.bitmap.blocks[block_index].key * block_size + lows[low_index]
  let next_low_index = low_index + 1
  let next_block_index = if next_low_index == lows.length() {
    block_index + 1
  } else {
    block_index
  }
  (
    Some(value),
    {
      bitmap: self.bitmap,
      block_index: next_block_index,
      lows,
      low_index: next_low_index,
      yielded: self.yielded + 1,
    },
  )
}

///|
/// Number of values not yet returned by this cursor.
pub fn RoaringCursor::remaining(self : RoaringCursor) -> Int {
  self.bitmap.cardinality() - self.yielded
}

///|
/// Union every bitmap in `bitmaps`. The identity for an empty input is empty.
pub fn union_all(bitmaps : Array[RoaringBitmap]) -> RoaringBitmap {
  let mut result = RoaringBitmap::new()
  for bitmap in bitmaps {
    result = result.union(bitmap)
  }
  result
}

///|
/// Intersect every bitmap in `bitmaps`. The identity for an empty input is empty.
pub fn intersection_all(bitmaps : Array[RoaringBitmap]) -> RoaringBitmap {
  if bitmaps.length() == 0 {
    return RoaringBitmap::new()
  }
  let mut result = bitmaps[0]
  for index in 1..<bitmaps.length() {
    result = result.intersection(bitmaps[index])
    if result.is_empty() {
      return result
    }
  }
  result
}

///|
/// Symmetric-difference every bitmap in `bitmaps`. The empty identity is empty.
pub fn xor_all(bitmaps : Array[RoaringBitmap]) -> RoaringBitmap {
  let mut result = RoaringBitmap::new()
  for bitmap in bitmaps {
    result = result.xor(bitmap)
  }
  result
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
