///|
/// A self-checking stable word frame around a supported codec payload.
pub(all) struct BitmapFrame {
  format : CodecFormat
  payload : Array[Int]
  checksum : Int
}

///|
/// Errors for framed transport validation.
pub(all) enum FrameError {
  Codec(CodecError)
  ChecksumMismatch(Int, Int)
}

///|
/// Encode a bitmap and record a deterministic checksum of the resulting words.
pub fn RoaringBitmap::frame(
  self : RoaringBitmap,
  format : CodecFormat,
) -> Result[BitmapFrame, CodecError] {
  match self.encode(format) {
    Ok(payload) => Ok({ format, checksum: frame_checksum(payload), payload, })
    Err(error) => Err(error)
  }
}

///|
/// Validate a frame checksum before decoding it.
pub fn BitmapFrame::decode(
  self : BitmapFrame,
) -> Result[RoaringBitmap, FrameError] {
  let actual = frame_checksum(self.payload)
  if actual != self.checksum {
    return Err(ChecksumMismatch(self.checksum, actual))
  }
  match decode(self.format, self.payload) {
    Ok(bitmap) => Ok(bitmap)
    Err(error) => Err(Codec(error))
  }
}

///|
/// Replace a frame payload for corruption-testing or transport adapters.
pub fn BitmapFrame::with_payload(
  self : BitmapFrame,
  payload : Array[Int],
) -> BitmapFrame {
  { format: self.format, checksum: self.checksum, payload, }
}

///|
/// A target-independent bounded checksum; it is corruption detection, not cryptography.
fn frame_checksum(words : Array[Int]) -> Int {
  let mut total = 17
  for word in words {
    let part = if word < 0 { -word % 1_000_003 } else { word % 1_000_003 }
    total = (total + part + 31) % 2_000_000_011
  }
  total
}
