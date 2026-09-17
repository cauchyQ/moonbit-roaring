///|
/// Cursor for ascending traversal without exposing container internals.
pub struct RoaringCursor {
  values : Array[Int]
  index : Int
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
  Ok(self.to_array().filter(value => start <= value && value < end).length())
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
