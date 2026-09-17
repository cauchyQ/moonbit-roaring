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
  RangeTooLarge(Int)
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

///| The maximum number of individual values accepted by range constructors.

///|
/// Range operations currently materialize their members before choosing a
/// container. Keeping this ceiling explicit prevents an accidental request for
/// a near-whole-domain range from exhausting memory.
let max_materialized_range = 1_000_000

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
    match self.blocks[0].container.minimum() {
      Some(low) => Some(self.blocks[0].key * block_size + low)
      None => None
    }
  }
}

///|
pub fn RoaringBitmap::maximum(self : RoaringBitmap) -> Int? {
  if self.is_empty() {
    None
  } else {
    let last = self.blocks[self.blocks.length() - 1]
    match last.container.maximum() {
      Some(low) => Some(last.key * block_size + low)
      None => None
    }
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
  let key = value / block_size
  let low = value % block_size
  for block in self.blocks {
    if block.key == key {
      return block.container.contains(low)
    }
    if block.key > key {
      return false
    }
  }
  false
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
  if end - start > max_materialized_range {
    return Err(RangeTooLarge(end - start))
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
  union_blocks(self.blocks, other.blocks)
}

///|
/// Intersection of two bitmaps.
pub fn RoaringBitmap::intersection(
  self : RoaringBitmap,
  other : RoaringBitmap,
) -> RoaringBitmap {
  intersection_blocks(self.blocks, other.blocks)
}

///|
/// Set difference `self - other`.
pub fn RoaringBitmap::difference(
  self : RoaringBitmap,
  other : RoaringBitmap,
) -> RoaringBitmap {
  difference_blocks(self.blocks, other.blocks)
}

///|
/// Symmetric difference of two bitmaps.
pub fn RoaringBitmap::xor(
  self : RoaringBitmap,
  other : RoaringBitmap,
) -> RoaringBitmap {
  xor_blocks(self.blocks, other.blocks)
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
  if value < 0 {
    return 0
  }
  let key = value / block_size
  let low = value % block_size
  let mut total = 0
  for block in self.blocks {
    if block.key < key {
      total += block.container.cardinality()
    } else if block.key == key {
      return total + block.container.rank(low)
    } else {
      return total
    }
  }
  total
}

///|
/// The zero-based `index`th value, if present.
pub fn RoaringBitmap::select(self : RoaringBitmap, index : Int) -> Int? {
  if index < 0 || index >= self.cardinality() {
    return None
  }
  let mut remaining = index
  for block in self.blocks {
    let count = block.container.cardinality()
    if remaining < count {
      match block.container.select(remaining) {
        Some(low) => return Some(block.key * block_size + low)
        None => return None
      }
    }
    remaining -= count
  }
  None
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
/// Merge blocks for union, dispatching work only when high-16-bit keys match.
fn union_blocks(
  left : Array[RoaringBlock],
  right : Array[RoaringBlock],
) -> RoaringBitmap {
  let output : Array[RoaringBlock] = []
  let mut a = 0
  let mut b = 0
  while a < left.length() || b < right.length() {
    if b == right.length() || (a < left.length() && left[a].key < right[b].key) {
      output.push(left[a])
      a += 1
    } else if a == left.length() || right[b].key < left[a].key {
      output.push(right[b])
      b += 1
    } else {
      output.push({
        key: left[a].key,
        container: left[a].container.union(right[b].container),
      })
      a += 1
      b += 1
    }
  }
  { blocks: output }
}

///|
/// Merge blocks for intersection.
fn intersection_blocks(
  left : Array[RoaringBlock],
  right : Array[RoaringBlock],
) -> RoaringBitmap {
  let output : Array[RoaringBlock] = []
  let mut a = 0
  let mut b = 0
  while a < left.length() && b < right.length() {
    if left[a].key < right[b].key {
      a += 1
    } else if right[b].key < left[a].key {
      b += 1
    } else {
      let container = left[a].container.intersection(right[b].container)
      if container.cardinality() > 0 {
        output.push({ key: left[a].key, container })
      }
      a += 1
      b += 1
    }
  }
  { blocks: output }
}

///|
/// Merge blocks for left difference.
fn difference_blocks(
  left : Array[RoaringBlock],
  right : Array[RoaringBlock],
) -> RoaringBitmap {
  let output : Array[RoaringBlock] = []
  let mut a = 0
  let mut b = 0
  while a < left.length() {
    while b < right.length() && right[b].key < left[a].key {
      b += 1
    }
    if b == right.length() || left[a].key < right[b].key {
      output.push(left[a])
    } else {
      let container = left[a].container.difference(right[b].container)
      if container.cardinality() > 0 {
        output.push({ key: left[a].key, container })
      }
    }
    a += 1
  }
  { blocks: output }
}

///|
/// Merge blocks for symmetric difference.
fn xor_blocks(
  left : Array[RoaringBlock],
  right : Array[RoaringBlock],
) -> RoaringBitmap {
  let output : Array[RoaringBlock] = []
  let mut a = 0
  let mut b = 0
  while a < left.length() || b < right.length() {
    if b == right.length() || (a < left.length() && left[a].key < right[b].key) {
      output.push(left[a])
      a += 1
    } else if a == left.length() || right[b].key < left[a].key {
      output.push(right[b])
      b += 1
    } else {
      let container = left[a].container.xor(right[b].container)
      if container.cardinality() > 0 {
        output.push({ key: left[a].key, container })
      }
      a += 1
      b += 1
    }
  }
  { blocks: output }
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
/// Container-local union. This avoids flattening unrelated high-16-bit blocks.
fn Container::union(self : Container, other : Container) -> Container {
  Container::from_lows(union_sorted(self.values(), other.values()))
}

///|
/// Container-local intersection.
fn Container::intersection(self : Container, other : Container) -> Container {
  Container::from_lows(intersection_sorted(self.values(), other.values()))
}

///|
/// Container-local difference.
fn Container::difference(self : Container, other : Container) -> Container {
  Container::from_lows(difference_sorted(self.values(), other.values()))
}

///|
/// Container-local symmetric difference.
fn Container::xor(self : Container, other : Container) -> Container {
  let left_only = difference_sorted(self.values(), other.values())
  let right_only = difference_sorted(other.values(), self.values())
  Container::from_lows(union_sorted(left_only, right_only))
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
/// Membership in one low-16-bit container.
fn Container::contains(self : Container, low : Int) -> Bool {
  match self {
    ArrayContainer(values) => values.contains(low)
    BitmapContainer(words, _) =>
      (words[low / word_bits] & (1 << (low % word_bits))) != 0
    RunContainer(runs, _) => {
      for run in runs {
        if run.start <= low && low <= run.end {
          return true
        }
        if run.start > low {
          return false
        }
      }
      false
    }
  }
}

///|
/// Number of container values less than or equal to `low`.
fn Container::rank(self : Container, low : Int) -> Int {
  match self {
    ArrayContainer(values) => values.filter(value => value <= low).length()
    BitmapContainer(_, _) =>
      self.values().filter(value => value <= low).length()
    RunContainer(runs, _) => {
      let mut total = 0
      for run in runs {
        if low < run.start {
          return total
        }
        total += if low < run.end {
          low - run.start + 1
        } else {
          run.end - run.start + 1
        }
        if low <= run.end {
          return total
        }
      }
      total
    }
  }
}

///|
/// Select a low value by zero-based index.
fn Container::select(self : Container, index : Int) -> Int? {
  match self {
    ArrayContainer(values) => Some(values[index])
    BitmapContainer(_, _) => Some(self.values()[index])
    RunContainer(runs, _) => {
      let mut remaining = index
      for run in runs {
        let length = run.end - run.start + 1
        if remaining < length {
          return Some(run.start + remaining)
        }
        remaining -= length
      }
      None
    }
  }
}

///|
/// First low value, if any.
fn Container::minimum(self : Container) -> Int? {
  match self {
    ArrayContainer(values) => Some(values[0])
    BitmapContainer(_, _) => self.select(0)
    RunContainer(runs, _) => Some(runs[0].start)
  }
}

///|
/// Last low value, if any.
fn Container::maximum(self : Container) -> Int? {
  match self {
    ArrayContainer(values) => Some(values[values.length() - 1])
    BitmapContainer(_, count) => self.select(count - 1)
    RunContainer(runs, _) => Some(runs[runs.length() - 1].end)
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
