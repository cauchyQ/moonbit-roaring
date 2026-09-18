///|
/// Stable word encodings supported by this module.
pub(all) enum CodecFormat {
  PlainWords
  RunWords
}

///|
pub fn RoaringBitmap::encode(
  self : RoaringBitmap,
  format : CodecFormat,
) -> Result[Array[Int], CodecError] {
  match format {
    PlainWords => Ok(self.encode_words())
    RunWords => self.encode_run_words()
  }
}

///|
pub fn decode(
  format : CodecFormat,
  words : Array[Int],
) -> Result[RoaringBitmap, CodecError] {
  match format {
    PlainWords => decode_words(words)
    RunWords => decode_run_words(words)
  }
}

///|
/// Decode one supported format and re-encode it canonically as another.
pub fn transcode(
  words : Array[Int],
  from : CodecFormat,
  to : CodecFormat,
) -> Result[Array[Int], CodecError] {
  match decode(from, words) {
    Ok(bitmap) => bitmap.encode(to)
    Err(error) => Err(error)
  }
}

///|
/// Inspect a stable word header without decoding its payload.
pub fn detect_codec(words : Array[Int]) -> Result[CodecFormat, CodecError] {
  if words.length() == 0 {
    return Err(MissingHeader)
  }
  match words[0] {
    1 => Ok(PlainWords)
    3 => Ok(RunWords)
    version => Err(UnsupportedVersion(version))
  }
}

///|
/// Decode a supported payload using its own version header.
pub fn decode_auto(words : Array[Int]) -> Result[RoaringBitmap, CodecError] {
  match detect_codec(words) {
    Ok(format) => decode(format, words)
    Err(error) => Err(error)
  }
}
