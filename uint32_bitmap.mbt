///|
/// An unsigned 32-bit bitmap divided into four non-negative Int shards.
/// Each shard contains at most 2^30 values, so its Int cardinality cannot overflow.
pub struct UInt32Bitmap {
  shards : Array[RoaringBitmap]
}

///|
pub fn UInt32Bitmap::new() -> UInt32Bitmap {
  {
    shards: [
      RoaringBitmap::new(),
      RoaringBitmap::new(),
      RoaringBitmap::new(),
      RoaringBitmap::new(),
    ],
  }
}

///|
pub fn UInt32Bitmap::add(self : UInt32Bitmap, value : UInt32) -> UInt32Bitmap {
  let index = (value >> 30).reinterpret_as_int()
  let low = (value & 0x3fffffffU).reinterpret_as_int()
  let shards = self.shards.copy()
  shards[index] = shards[index].add(low).unwrap()
  { shards, }
}

///|
pub fn UInt32Bitmap::remove(
  self : UInt32Bitmap,
  value : UInt32,
) -> UInt32Bitmap {
  let index = (value >> 30).reinterpret_as_int()
  let low = (value & 0x3fffffffU).reinterpret_as_int()
  let shards = self.shards.copy()
  shards[index] = shards[index].remove(low)
  { shards, }
}

///|
pub fn UInt32Bitmap::contains(self : UInt32Bitmap, value : UInt32) -> Bool {
  let index = (value >> 30).reinterpret_as_int()
  self.shards[index].contains((value & 0x3fffffffU).reinterpret_as_int())
}

///|
pub fn UInt32Bitmap::cardinality(self : UInt32Bitmap) -> UInt64 {
  let mut total = 0UL
  for shard in self.shards {
    total += shard.cardinality().to_uint64()
  }
  total
}

///|
pub fn UInt32Bitmap::union(
  self : UInt32Bitmap,
  other : UInt32Bitmap,
) -> UInt32Bitmap {
  let shards : Array[RoaringBitmap] = []
  for index in 0..<4 {
    shards.push(self.shards[index].union(other.shards[index]))
  }
  { shards, }
}

///|
pub fn UInt32Bitmap::intersection(
  self : UInt32Bitmap,
  other : UInt32Bitmap,
) -> UInt32Bitmap {
  let shards : Array[RoaringBitmap] = []
  for index in 0..<4 {
    shards.push(self.shards[index].intersection(other.shards[index]))
  }
  { shards, }
}

///|
pub fn UInt32Bitmap::difference(
  self : UInt32Bitmap,
  other : UInt32Bitmap,
) -> UInt32Bitmap {
  let shards : Array[RoaringBitmap] = []
  for index in 0..<4 {
    shards.push(self.shards[index].difference(other.shards[index]))
  }
  { shards, }
}

///|
/// Symmetric difference of two unsigned bitmaps.
pub fn UInt32Bitmap::xor(
  self : UInt32Bitmap,
  other : UInt32Bitmap,
) -> UInt32Bitmap {
  let shards : Array[RoaringBitmap] = []
  for index in 0..<4 {
    shards.push(self.shards[index].xor(other.shards[index]))
  }
  { shards, }
}

///|
/// Add a half-open range; the endpoint 2^32 includes the maximum UInt value.
pub fn UInt32Bitmap::add_range(
  self : UInt32Bitmap,
  start : UInt64,
  end : UInt64,
) -> Result[UInt32Bitmap, String] {
  if start > end || end > 4294967296UL {
    return Err("invalid UInt32 range")
  }
  let shards = self.shards.copy()
  let mut cursor = start
  while cursor < end {
    let index = (cursor / 1073741824UL).to_int()
    let shard_start = (cursor % 1073741824UL).to_int()
    let remaining = end - cursor
    let available = 1073741824 - shard_start
    let length = if remaining < available.to_uint64() {
      remaining.to_int()
    } else {
      available
    }
    let mut offset = 0
    while offset < length {
      let step = if length - offset > 1000000 {
        1000000
      } else {
        length - offset
      }
      match
        shards[index].add_range(
          shard_start + offset,
          shard_start + offset + step,
        ) {
        Ok(bitmap) => shards[index] = bitmap
        Err(_) => return Err("failed to add range")
      }
      offset += step
    }
    cursor += length.to_uint64()
  }
  Ok({ shards, })
}

///|
/// Remove a half-open unsigned range.
pub fn UInt32Bitmap::remove_range(
  self : UInt32Bitmap,
  start : UInt64,
  end : UInt64,
) -> Result[UInt32Bitmap, String] {
  if start > end || end > 4294967296UL {
    return Err("invalid UInt32 range")
  }
  let shards = self.shards.copy()
  let mut cursor = start
  while cursor < end {
    let index = (cursor / 1073741824UL).to_int()
    let shard_start = (cursor % 1073741824UL).to_int()
    let remaining = end - cursor
    let available = 1073741824 - shard_start
    let length = if remaining < available.to_uint64() {
      remaining.to_int()
    } else {
      available
    }
    match shards[index].remove_range(shard_start, shard_start + length) {
      Ok(bitmap) => shards[index] = bitmap
      Err(_) => return Err("failed to remove range")
    }
    cursor += length.to_uint64()
  }
  Ok({ shards, })
}

///|
/// Number of members less than or equal to value.
pub fn UInt32Bitmap::rank(self : UInt32Bitmap, value : UInt32) -> UInt64 {
  let index = (value >> 30).reinterpret_as_int()
  let mut count = 0UL
  for i in 0..<index {
    count += self.shards[i].cardinality().to_uint64()
  }
  count +
  self.shards[index]
  .rank((value & 0x3fffffffU).reinterpret_as_int())
  .to_uint64()
}

///|
/// Select the value at a zero-based position.
pub fn UInt32Bitmap::select(self : UInt32Bitmap, index : UInt64) -> UInt32? {
  let mut remaining = index
  for i in 0..<4 {
    let size = self.shards[i].cardinality().to_uint64()
    if remaining < size {
      return match self.shards[i].select(remaining.to_int()) {
        Some(low) =>
          Some((i.reinterpret_as_uint() << 30) | low.reinterpret_as_uint())
        None => None
      }
    }
    remaining -= size
  }
  None
}

///|
/// Portable output without flattening the full bitmap.
pub fn UInt32Bitmap::serialize_portable(
  self : UInt32Bitmap,
) -> Result[Bytes, String] {
  let containers : Array[RoaringBlock] = []
  for i in 0..<4 {
    for block in self.shards[i].blocks {
      containers.push({
        key: i * 16384 + block.key,
        container: block.container,
      })
    }
  }
  let buf = @buffer.Buffer::Buffer()
  buf.write_uint_le(12346U)
  buf.write_int_le(containers.length())
  for block in containers {
    buf.write_uint16_le(block.key.to_uint16())
    buf.write_uint16_le((block.container.cardinality() - 1).to_uint16())
  }
  let mut offset = 8 + containers.length() * 8
  for block in containers {
    buf.write_int_le(offset)
    let count = block.container.cardinality()
    offset += if count <= 4096 { count * 2 } else { 8192 }
  }
  for block in containers {
    let lows = block.container.values()
    if lows.length() <= 4096 {
      for low in lows {
        buf.write_uint16_le(low.to_uint16())
      }
    } else {
      for word in make_words(lows) {
        buf.write_int_le(word)
      }
    }
  }
  Ok(buf.to_bytes())
}

///|
/// Portable encoding with Run containers where they reduce encoded size.
/// The no-run writer remains the canonical representation for URP1 digests.
pub fn UInt32Bitmap::serialize_portable_compact(self : UInt32Bitmap) -> Bytes {
  let blocks : Array[RoaringBlock] = []
  let runs_by_block : Array[Array[Run]] = []
  let run_flags : Array[Bool] = []
  let mut any_run = false
  for shard in 0..<4 {
    for block in self.shards[shard].blocks {
      blocks.push({
        key: shard * 16384 + block.key,
        container: block.container,
      })
      let lows = block.container.values()
      let runs = make_runs(lows)
      let ordinary_size = if lows.length() <= 4096 {
        lows.length() * 2
      } else {
        8192
      }
      let use_run = 2 + runs.length() * 4 < ordinary_size
      runs_by_block.push(runs)
      run_flags.push(use_run)
      any_run = any_run || use_run
    }
  }
  if !any_run {
    return self.serialize_portable().unwrap()
  }
  let size = blocks.length()
  let buf = @buffer.Buffer::Buffer()
  buf.write_uint_le(12347U | ((size - 1).reinterpret_as_uint() << 16))
  for byte_index in 0..<((size + 7) / 8) {
    let mut flag = 0
    for bit in 0..<8 {
      let index = byte_index * 8 + bit
      if index < size && run_flags[index] {
        flag = flag | (1 << bit)
      }
    }
    buf.write_byte(flag.to_byte())
  }
  for block in blocks {
    buf.write_uint16_le(block.key.to_uint16())
    buf.write_uint16_le((block.container.cardinality() - 1).to_uint16())
  }
  if size >= 4 {
    let mut offset = 4 + (size + 7) / 8 + size * 8
    for i in 0..<size {
      buf.write_int_le(offset)
      let count = blocks[i].container.cardinality()
      offset += if run_flags[i] {
        2 + runs_by_block[i].length() * 4
      } else if count <= 4096 {
        count * 2
      } else {
        8192
      }
    }
  }
  for i in 0..<size {
    if run_flags[i] {
      buf.write_uint16_le(runs_by_block[i].length().to_uint16())
      for run in runs_by_block[i] {
        buf.write_uint16_le(run.start.to_uint16())
        buf.write_uint16_le((run.end - run.start).to_uint16())
      }
    } else {
      let lows = blocks[i].container.values()
      if lows.length() <= 4096 {
        for low in lows {
          buf.write_uint16_le(low.to_uint16())
        }
      } else {
        for word in make_words(lows) {
          buf.write_int_le(word)
        }
      }
    }
  }
  buf.to_bytes()
}

///|
/// Read portable data with a bounded per-container conversion buffer.
pub fn decode_portable_uint32(bytes : Bytes) -> Result[UInt32Bitmap, String] {
  let bitmap = match @portable.RoaringBitmap::deserialize(bytes) {
    Ok(value) => value
    Err(error) => return Err(error.to_string())
  }
  let grouped : Array[Array[RoaringBlock]] = [[], [], [], []]
  let mut key = -1
  let mut lows : Array[Int32] = []
  for value in bitmap.iter() {
    let next_key = (value >> 16).reinterpret_as_int()
    if key != next_key && key >= 0 {
      grouped[key / 16384].push({
        key: key % 16384,
        container: Container::from_lows(lows),
      })
      lows = []
    }
    key = next_key
    lows.push((value & 65535U).reinterpret_as_int())
  }
  if key >= 0 {
    grouped[key / 16384].push({
      key: key % 16384,
      container: Container::from_lows(lows),
    })
  }
  let shards : Array[RoaringBitmap] = []
  for blocks in grouped {
    shards.push({ blocks, })
  }
  Ok({ shards, })
}
