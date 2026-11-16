///|
/// An immutable unsigned bitmap snapshot identified by dataset and version.
pub struct UInt32Snapshot {
  dataset : String
  generation : UInt64
  bitmap : UInt32Bitmap
}

///|
/// A checked in-memory delta between two snapshots.
pub struct UInt32SnapshotPatch {
  dataset : String
  base_generation : UInt64
  target_generation : UInt64
  base_digest : Bytes
  target_digest : Bytes
  additions : UInt32Bitmap
  removals : UInt32Bitmap
}

///|
pub fn UInt32Snapshot::new(
  dataset : String,
  generation : UInt64,
  bitmap : UInt32Bitmap,
) -> UInt32Snapshot {
  { dataset, generation, bitmap, }
}

///|
pub fn UInt32Snapshot::bitmap(self : UInt32Snapshot) -> UInt32Bitmap {
  self.bitmap
}

///|
pub fn UInt32Snapshot::generation(self : UInt32Snapshot) -> UInt64 {
  self.generation
}

///|
pub fn UInt32Snapshot::diff_to(
  self : UInt32Snapshot,
  target : UInt32Snapshot,
) -> Result[UInt32SnapshotPatch, String] {
  if self.dataset != target.dataset {
    return Err("dataset mismatch")
  }
  if target.generation <= self.generation {
    return Err("target generation must increase")
  }
  Ok({
    dataset: self.dataset,
    base_generation: self.generation,
    target_generation: target.generation,
    base_digest: content_digest(self.bitmap.serialize_portable().unwrap()),
    target_digest: content_digest(target.bitmap.serialize_portable().unwrap()),
    additions: target.bitmap.difference(self.bitmap),
    removals: self.bitmap.difference(target.bitmap),
  })
}

///|
/// Apply only to the exact dataset, generation and bitmap used as the base.
pub fn UInt32Snapshot::apply(
  self : UInt32Snapshot,
  patch : UInt32SnapshotPatch,
) -> Result[UInt32Snapshot, String] {
  if self.dataset != patch.dataset || self.generation != patch.base_generation {
    return Err("snapshot identity mismatch")
  }
  if content_digest(self.bitmap.serialize_portable().unwrap()) !=
    patch.base_digest {
    return Err("snapshot baseline mismatch")
  }
  let bitmap = self.bitmap.difference(patch.removals).union(patch.additions)
  if content_digest(bitmap.serialize_portable().unwrap()) != patch.target_digest {
    return Err("snapshot target mismatch")
  }
  Ok({ dataset: self.dataset, generation: patch.target_generation, bitmap, })
}

///|
/// Version 1 patch: magic, dataset digest, generations, content digests,
/// payload lengths, then two standard portable bitmaps. All numbers little endian.
pub fn UInt32SnapshotPatch::serialize(self : UInt32SnapshotPatch) -> Bytes {
  let name = @buffer.Buffer::Buffer()
  name.write_string_utf8(self.dataset[:])
  let added = self.additions.serialize_portable_compact()
  let removed = self.removals.serialize_portable_compact()
  let out = @buffer.Buffer::Buffer()
  out.write_bytes(b"URP1"[:])
  out.write_bytes(content_digest(name.to_bytes())[:])
  out.write_uint64_le(self.base_generation)
  out.write_uint64_le(self.target_generation)
  out.write_bytes(self.base_digest[:])
  out.write_bytes(self.target_digest[:])
  out.write_int_le(added.length())
  out.write_int_le(removed.length())
  out.write_bytes(added[:])
  out.write_bytes(removed[:])
  out.to_bytes()
}

///|
/// Decode a patch for the expected dataset, rejecting trailing or truncated data.
pub fn decode_uint32_patch(
  data : Bytes,
  dataset : String,
) -> Result[UInt32SnapshotPatch, String] {
  if data.length() < 124 || data[0:4].to_owned() != b"URP1" {
    return Err("invalid patch header")
  }
  let name = @buffer.Buffer::Buffer()
  name.write_string_utf8(dataset[:])
  if data[4:36].to_owned() != content_digest(name.to_bytes()) {
    return Err("dataset mismatch")
  }
  let base_generation = data.unsafe_read_uint64_le(36)
  let target_generation = data.unsafe_read_uint64_le(44)
  if target_generation <= base_generation {
    return Err("invalid patch generations")
  }
  let added_length = data.unsafe_read_uint32_le(116).reinterpret_as_int()
  let removed_length = data.unsafe_read_uint32_le(120).reinterpret_as_int()
  if added_length < 0 ||
    removed_length < 0 ||
    added_length > data.length() - 124 {
    return Err("invalid patch lengths")
  }
  let split = 124 + added_length
  if removed_length != data.length() - split {
    return Err("invalid patch lengths")
  }
  let additions = match decode_portable_uint32(data[124:split].to_owned()) {
    Ok(bitmap) => bitmap
    Err(error) => return Err(error)
  }
  let removals = match decode_portable_uint32(data[split:].to_owned()) {
    Ok(bitmap) => bitmap
    Err(error) => return Err(error)
  }
  if additions.intersection(removals).cardinality() != 0UL {
    return Err("conflicting patch")
  }
  Ok({
    dataset,
    base_generation,
    target_generation,
    base_digest: data[52:84].to_owned(),
    target_digest: data[84:116].to_owned(),
    additions,
    removals,
  })
}
