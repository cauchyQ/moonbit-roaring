///|
/// Compact summary of the numeric extent of a bitmap.
pub(all) struct BitmapProfile {
  cardinality : Int
  minimum : Int?
  maximum : Int?
  span : Int
  block_count : Int
}

///|
/// Inspect cardinality and extent without exposing container internals.
pub fn RoaringBitmap::profile(self : RoaringBitmap) -> BitmapProfile {
  let minimum = self.minimum()
  let maximum = self.maximum()
  let span = match (minimum, maximum) {
    (Some(start), Some(end)) => end - start + 1
    _ => 0
  }
  {
    cardinality: self.cardinality(),
    minimum,
    maximum,
    span,
    block_count: self.stats().block_count,
  }
}

///|
/// Return numerator and denominator for exact Jaccard similarity.
/// Callers can choose their own floating-point representation if required.
pub fn RoaringBitmap::jaccard_parts(
  self : RoaringBitmap,
  other : RoaringBitmap,
) -> (Int, Int) {
  (self.intersection(other).cardinality(), self.union(other).cardinality())
}

///|
/// Return a stable, evenly distributed sample in ascending order.
pub fn RoaringBitmap::sample_evenly(
  self : RoaringBitmap,
  count : Int,
) -> Array[Int] {
  let output : Array[Int] = []
  let total = self.cardinality()
  if count <= 0 || total == 0 {
    return output
  }
  let actual = if count < total { count } else { total }
  for index in 0..<actual {
    let position = index * total / actual
    match self.select(position) {
      Some(value) => output.push(value)
      None => ()
    }
  }
  output
}

///|
/// Select the value at an exact rational quantile in `[0, denominator]`.
pub fn RoaringBitmap::quantile(
  self : RoaringBitmap,
  numerator : Int,
  denominator : Int,
) -> Result[Int?, RoaringError] {
  if denominator <= 0 || numerator < 0 || numerator > denominator {
    return Err(InvalidRange(numerator, denominator))
  }
  let total = self.cardinality()
  if total == 0 {
    return Ok(None)
  }
  Ok(self.select(numerator * (total - 1) / denominator))
}
