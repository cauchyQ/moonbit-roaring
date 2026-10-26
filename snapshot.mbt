///|
/// An immutable bitmap state identified by a monotonically increasing generation.
pub struct RoaringSnapshot {
  generation : Int
  bitmap : RoaringBitmap
}

///|
/// Errors at snapshot generation and frame boundaries.
pub(all) enum SnapshotError {
  InvalidGeneration(Int)
  GenerationOverflow(Int)
  StaleGeneration(Int, Int)
  Frame(FrameError)
}

///|
/// A transportable snapshot envelope with its self-checking bitmap frame.
pub(all) struct SnapshotEnvelope {
  generation : Int
  frame : BitmapFrame
}

///|
/// A checked patch between two exact snapshot generations.
pub(all) struct SnapshotPatchEnvelope {
  base_generation : Int
  target_generation : Int
  additions : BitmapFrame
  removals : BitmapFrame
}

///|
/// Create generation zero from a bitmap.
pub fn RoaringSnapshot::new(bitmap : RoaringBitmap) -> RoaringSnapshot {
  { generation: 0, bitmap, }
}

///|
/// Create a snapshot at an explicit non-negative generation.
pub fn RoaringSnapshot::at(
  generation : Int,
  bitmap : RoaringBitmap,
) -> Result[RoaringSnapshot, SnapshotError] {
  if generation < 0 {
    Err(InvalidGeneration(generation))
  } else {
    Ok({ generation, bitmap, })
  }
}

///|
/// Return the snapshot generation.
pub fn RoaringSnapshot::generation(self : RoaringSnapshot) -> Int {
  self.generation
}

///|
/// Return the immutable bitmap held by this snapshot.
pub fn RoaringSnapshot::bitmap(self : RoaringSnapshot) -> RoaringBitmap {
  self.bitmap
}

///|
/// Apply a patch and advance exactly one generation.
pub fn RoaringSnapshot::advance(
  self : RoaringSnapshot,
  patch : RoaringPatch,
) -> Result[RoaringSnapshot, SnapshotError] {
  if self.generation == 2_147_483_647 {
    return Err(GenerationOverflow(self.generation))
  }
  Ok({ generation: self.generation + 1, bitmap: patch.apply(self.bitmap), })
}

///|
/// Produce the exact patch needed to reach another snapshot.
pub fn RoaringSnapshot::diff_to(
  self : RoaringSnapshot,
  target : RoaringSnapshot,
) -> RoaringPatch {
  self.bitmap.diff_to(target.bitmap)
}

///|
/// Wrap this snapshot in an integrity-checked frame.
pub fn RoaringSnapshot::envelope(
  self : RoaringSnapshot,
  format : CodecFormat,
) -> Result[SnapshotEnvelope, CodecError] {
  match self.bitmap.frame(format) {
    Ok(frame) => Ok({ generation: self.generation, frame, })
    Err(error) => Err(error)
  }
}

///|
/// Recover a snapshot after validating its transport frame.
pub fn SnapshotEnvelope::decode(
  self : SnapshotEnvelope,
) -> Result[RoaringSnapshot, SnapshotError] {
  if self.generation < 0 {
    return Err(InvalidGeneration(self.generation))
  }
  match self.frame.decode() {
    Ok(bitmap) => Ok({ generation: self.generation, bitmap, })
    Err(error) => Err(Frame(error))
  }
}

///|
/// Return envelope generation without decoding its payload.
pub fn SnapshotEnvelope::generation(self : SnapshotEnvelope) -> Int {
  self.generation
}

///|
/// Encode the exact delta from this snapshot to `target`.
pub fn RoaringSnapshot::patch_envelope(
  self : RoaringSnapshot,
  target : RoaringSnapshot,
  format : CodecFormat,
) -> Result[SnapshotPatchEnvelope, CodecError] {
  let patch = self.diff_to(target)
  match patch.additions.frame(format) {
    Err(error) => Err(error)
    Ok(additions) =>
      match patch.removals.frame(format) {
        Err(error) => Err(error)
        Ok(removals) =>
          Ok({
            base_generation: self.generation,
            target_generation: target.generation,
            additions,
            removals,
          })
      }
  }
}

///|
/// Apply a checked patch only when its base generation matches this snapshot.
pub fn RoaringSnapshot::apply_patch_envelope(
  self : RoaringSnapshot,
  envelope : SnapshotPatchEnvelope,
) -> Result[RoaringSnapshot, SnapshotError] {
  if envelope.base_generation != self.generation {
    return Err(StaleGeneration(self.generation, envelope.base_generation))
  }
  if envelope.target_generation < 0 {
    return Err(InvalidGeneration(envelope.target_generation))
  }
  let additions = match envelope.additions.decode() {
    Ok(bitmap) => bitmap
    Err(error) => return Err(Frame(error))
  }
  let removals = match envelope.removals.decode() {
    Ok(bitmap) => bitmap
    Err(error) => return Err(Frame(error))
  }
  Ok({
    generation: envelope.target_generation,
    bitmap: self.bitmap.difference(removals).union(additions),
  })
}

///|
pub fn SnapshotPatchEnvelope::base_generation(
  self : SnapshotPatchEnvelope,
) -> Int {
  self.base_generation
}

///|
pub fn SnapshotPatchEnvelope::target_generation(
  self : SnapshotPatchEnvelope,
) -> Int {
  self.target_generation
}
