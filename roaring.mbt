///| A compressed set of non-negative `Int` values. Values are split by their

///|
/// high 16 bits; each block chooses an array, bitmap, or run representation.
pub struct RoaringBitmap {
  blocks : Array[RoaringBlock]
}

///|
/// One high-16-bit partition of a bitmap.
struct RoaringBlock {
  key : Int
  container : Container
}

///|
/// Inclusive low-16-bit run used for consecutive values.
priv struct Run {
  start : Int
  end : Int
}

///|
/// The three storage forms used by the bitmap.
priv enum Container {
  ArrayContainer(Array[Int])
  BitmapContainer(Array[Int], Int)
  RunContainer(Array[Run], Int)
}

///|
/// Input validation failures at the non-negative integer boundary.
pub(all) enum RoaringError {
  NegativeValue(Int)
  InvalidRange(Int, Int)
}

///|
pub(all) struct RoaringStats {
  block_count : Int
  array_blocks : Int
  bitmap_blocks : Int
  run_blocks : Int
  cardinality : Int
}

///|
let block_size = 65_536

///|
let bitmap_threshold = 4_096

///|
let word_bits = 32

///|
let word_count = 2_048

///|
/// Create an empty bitmap.
pub fn RoaringBitmap::new() -> RoaringBitmap {
  { blocks: [] }
}

///|
/// Build a normalized bitmap from non-negative integers.
pub fn RoaringBitmap::from_array(
  values : Array[Int],
) -> Result[RoaringBitmap, RoaringError] {
  for value in values {
    if !valid_value(value) {
      return Err(NegativeValue(value))
    }
  }
  Ok(from_sorted(normalize(values)))
}

///|
/// Return the values in ascending order.
pub fn RoaringBitmap::to_array(self : RoaringBitmap) -> Array[Int] {
  let output : Array[Int] = []
  for block in self.blocks {
    for low in block.container.values() {
      output.push(block.key * block_size + low)
    }
  }
  output
}

///|
/// Number of distinct values stored in the bitmap.
pub fn RoaringBitmap::cardinality(self : RoaringBitmap) -> Int {
  let mut total = 0
  for block in self.blocks {
    total += block.container.cardinality()
  }
  total
}

///|
pub fn RoaringBitmap::is_empty(self : RoaringBitmap) -> Bool {
  self.blocks.length() == 0
}

///|
pub fn RoaringBitmap::minimum(self : RoaringBitmap) -> Int? {
  if self.is_empty() {
    None
  } else {
    Some(self.to_array()[0])
  }
}

///|
pub fn RoaringBitmap::maximum(self : RoaringBitmap) -> Int? {
  let values = self.to_array()
  if values.length() == 0 {
    None
  } else {
    Some(values[values.length() - 1])
  }
}

///|
pub fn RoaringBitmap::stats(self : RoaringBitmap) -> RoaringStats {
  let mut arrays = 0
  let mut bitmaps = 0
  let mut runs = 0
  for block in self.blocks {
    match block.container {
      ArrayContainer(_) => arrays += 1
      BitmapContainer(_, _) => bitmaps += 1
      RunContainer(_, _) => runs += 1
    }
  }
  {
    block_count: self.blocks.length(),
    array_blocks: arrays,
    bitmap_blocks: bitmaps,
    run_blocks: runs,
    cardinality: self.cardinality(),
  }
}

///|
/// True when `value` belongs to this bitmap.
pub fn RoaringBitmap::contains(self : RoaringBitmap, value : Int) -> Bool {
  if !valid_value(value) {
    return false
  }
  self.to_array().contains(value)
}

///|
/// Insert one value. Insertion is idempotent and returns a new bitmap.
pub fn RoaringBitmap::add(
  self : RoaringBitmap,
  value : Int,
) -> Result[RoaringBitmap, RoaringError] {
  if !valid_value(value) {
    return Err(NegativeValue(value))
  }
  let values = self.to_array()
  values.push(value)
  Ok(from_sorted(normalize(values)))
}

///|
/// Remove one value. Removing an absent value is a no-op.
pub fn RoaringBitmap::remove(
  self : RoaringBitmap,
  value : Int,
) -> RoaringBitmap {
  from_sorted(self.to_array().filter(item => item != value))
}

///|
/// Add every value in the half-open range `[start, end)`.
pub fn RoaringBitmap::add_range(
  self : RoaringBitmap,
  start : Int,
  end : Int,
) -> Result[RoaringBitmap, RoaringError] {
  if start < 0 || end < start {
    return Err(InvalidRange(start, end))
  }
  let values = self.to_array()
  for value in start..<end {
    values.push(value)
  }
  Ok(from_sorted(normalize(values)))
}

///|
/// Union of two bitmaps.
pub fn RoaringBitmap::union(
  self : RoaringBitmap,
  other : RoaringBitmap,
) -> RoaringBitmap {
  from_sorted(union_sorted(self.to_array(), other.to_array()))
}

///|
/// Intersection of two bitmaps.
pub fn RoaringBitmap::intersection(
  self : RoaringBitmap,
  other : RoaringBitmap,
) -> RoaringBitmap {
  from_sorted(intersection_sorted(self.to_array(), other.to_array()))
}

///|
/// Set difference `self - other`.
pub fn RoaringBitmap::difference(
  self : RoaringBitmap,
  other : RoaringBitmap,
) -> RoaringBitmap {
  from_sorted(difference_sorted(self.to_array(), other.to_array()))
}

///|
/// Symmetric difference of two bitmaps.
pub fn RoaringBitmap::xor(
  self : RoaringBitmap,
  other : RoaringBitmap,
) -> RoaringBitmap {
  let left_only = difference_sorted(self.to_array(), other.to_array())
  let right_only = difference_sorted(other.to_array(), self.to_array())
  from_sorted(union_sorted(left_only, right_only))
}

///|
pub fn RoaringBitmap::intersects(
  self : RoaringBitmap,
  other : RoaringBitmap,
) -> Bool {
  !self.intersection(other).is_empty()
}

///|
pub fn RoaringBitmap::is_subset_of(
  self : RoaringBitmap,
  other : RoaringBitmap,
) -> Bool {
  self.difference(other).is_empty()
}

///|
/// Number of values less than or equal to `value`.
pub fn RoaringBitmap::rank(self : RoaringBitmap, value : Int) -> Int {
  self.to_array().filter(item => item <= value).length()
}

///|
/// The zero-based `index`th value, if present.
pub fn RoaringBitmap::select(self : RoaringBitmap, index : Int) -> Int? {
  if index < 0 || index >= self.cardinality() {
    None
  } else {
    Some(self.to_array()[index])
  }
}

///|
fn valid_value(value : Int) -> Bool {
  0 <= value
}

///|
fn normalize(values : Array[Int]) -> Array[Int] {
  let ordered = values.copy()
  ordered.sort()
  let output : Array[Int] = []
  for value in ordered {
    if output.length() == 0 || output[output.length() - 1] != value {
      output.push(value)
    }
  }
  output
}

///|
fn union_sorted(left : Array[Int], right : Array[Int]) -> Array[Int] {
  let output : Array[Int] = []
  let mut a = 0
  let mut b = 0
  while a < left.length() || b < right.length() {
    if b == right.length() || (a < left.length() && left[a] < right[b]) {
      output.push(left[a])
      a += 1
    } else if a == left.length() || right[b] < left[a] {
      output.push(right[b])
      b += 1
    } else {
      output.push(left[a])
      a += 1
      b += 1
    }
  }
  output
}

///|
fn intersection_sorted(left : Array[Int], right : Array[Int]) -> Array[Int] {
  let output : Array[Int] = []
  let mut a = 0
  let mut b = 0
  while a < left.length() && b < right.length() {
    if left[a] < right[b] {
      a += 1
    } else if right[b] < left[a] {
      b += 1
    } else {
      output.push(left[a])
      a += 1
      b += 1
    }
  }
  output
}

///|
fn difference_sorted(left : Array[Int], right : Array[Int]) -> Array[Int] {
  let output : Array[Int] = []
  let mut a = 0
  let mut b = 0
  while a < left.length() {
    while b < right.length() && right[b] < left[a] {
      b += 1
    }
    if b == right.length() || left[a] < right[b] {
      output.push(left[a])
    }
    a += 1
  }
  output
}

///|
fn from_sorted(values : Array[Int]) -> RoaringBitmap {
  let blocks : Array[RoaringBlock] = []
  let mut index = 0
  while index < values.length() {
    let key = values[index] / block_size
    let lows : Array[Int] = []
    while index < values.length() && values[index] / block_size == key {
      lows.push(values[index] % block_size)
      index += 1
    }
    blocks.push({ key, container: Container::from_lows(lows) })
  }
  { blocks, }
}

///|
fn Container::from_lows(lows : Array[Int]) -> Container {
  let runs = make_runs(lows)
  if lows.length() >= bitmap_threshold {
    BitmapContainer(make_words(lows), lows.length())
  } else if runs.length() * 2 < lows.length() {
    RunContainer(runs, lows.length())
  } else {
    ArrayContainer(lows)
  }
}

///|
fn Container::cardinality(self : Container) -> Int {
  match self {
    ArrayContainer(values) => values.length()
    BitmapContainer(_, count) => count
    RunContainer(_, count) => count
  }
}

///|
fn Container::values(self : Container) -> Array[Int] {
  match self {
    ArrayContainer(values) => values.copy()
    BitmapContainer(words, _) => {
      let output : Array[Int] = []
      for low in 0..<block_size {
        let word = words[low / word_bits]
        if (word & (1 << (low % word_bits))) != 0 {
          output.push(low)
        }
      }
      output
    }
    RunContainer(runs, _) => {
      let output : Array[Int] = []
      for run in runs {
        for low in run.start..<=run.end {
          output.push(low)
        }
      }
      output
    }
  }
}

///|
fn make_words(lows : Array[Int]) -> Array[Int] {
  let words : Array[Int] = []
  for _ in 0..<word_count {
    words.push(0)
  }
  for low in lows {
    let index = low / word_bits
    words[index] = words[index] | (1 << (low % word_bits))
  }
  words
}

///|
fn make_runs(lows : Array[Int]) -> Array[Run] {
  let output : Array[Run] = []
  if lows.length() == 0 {
    return output
  }
  let mut start = lows[0]
  let mut previous = start
  for index in 1..<lows.length() {
    let low = lows[index]
    if low != previous + 1 {
      output.push({ start, end: previous })
      start = low
    }
    previous = low
  }
  output.push({ start, end: previous })
  output
}
