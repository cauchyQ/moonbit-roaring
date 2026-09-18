///|
/// Parse failures for the versioned operation-journal word format.
pub(all) enum JournalCodecError {
  MissingHeader
  UnsupportedVersion(Int)
  InvalidOperationCount(Int)
  InvalidTag(Int)
  TruncatedPayload(Int)
  InvalidBatchCount(Int)
}

///|
/// Encode a replayable log as `[1, operation_count, tag, payload...]` words.
/// Tags 1-6 represent Add, Remove, AddRange, RemoveRange, AddAll, RemoveAll.
pub fn RoaringOperationLog::encode_words(
  self : RoaringOperationLog,
) -> Array[Int] {
  let output : Array[Int] = [1, self.operations.length()]
  for operation in self.operations {
    match operation {
      Add(value) => {
        output.push(1)
        output.push(value)
      }
      Remove(value) => {
        output.push(2)
        output.push(value)
      }
      AddRange(start, end) => {
        output.push(3)
        output.push(start)
        output.push(end)
      }
      RemoveRange(start, end) => {
        output.push(4)
        output.push(start)
        output.push(end)
      }
      AddAll(values) => {
        output.push(5)
        output.push(values.length())
        for value in values {
          output.push(value)
        }
      }
      RemoveAll(values) => {
        output.push(6)
        output.push(values.length())
        for value in values {
          output.push(value)
        }
      }
    }
  }
  output
}

///|
/// Decode a stable journal payload with a caller-provided checkpoint.
pub fn decode_operation_log(
  checkpoint : RoaringBitmap,
  words : Array[Int],
) -> Result[RoaringOperationLog, JournalCodecError] {
  if words.length() == 0 {
    return Err(MissingHeader)
  }
  if words[0] != 1 {
    return Err(UnsupportedVersion(words[0]))
  }
  if words.length() < 2 || words[1] < 0 {
    return Err(
      InvalidOperationCount(if words.length() < 2 { -1 } else { words[1] }),
    )
  }
  let expected = words[1]
  let mut index = 2
  let operations : Array[BitmapOperation] = []
  while operations.length() < expected {
    if index >= words.length() {
      return Err(TruncatedPayload(index))
    }
    let tag = words[index]
    index += 1
    if tag == 1 || tag == 2 {
      if index >= words.length() {
        return Err(TruncatedPayload(index))
      }
      let value = words[index]
      index += 1
      if tag == 1 {
        operations.push(Add(value))
      } else {
        operations.push(Remove(value))
      }
    } else if tag == 3 || tag == 4 {
      if index + 1 >= words.length() {
        return Err(TruncatedPayload(index))
      }
      let start = words[index]
      let end = words[index + 1]
      index += 2
      if tag == 3 {
        operations.push(AddRange(start, end))
      } else {
        operations.push(RemoveRange(start, end))
      }
    } else if tag == 5 || tag == 6 {
      if index >= words.length() {
        return Err(TruncatedPayload(index))
      }
      let count = words[index]
      index += 1
      if count < 0 || count > words.length() - index {
        return Err(InvalidBatchCount(count))
      }
      let values : Array[Int] = []
      for _ in 0..<count {
        values.push(words[index])
        index += 1
      }
      if tag == 5 {
        operations.push(AddAll(values))
      } else {
        operations.push(RemoveAll(values))
      }
    } else {
      return Err(InvalidTag(tag))
    }
  }
  if index != words.length() {
    return Err(TruncatedPayload(index))
  }
  Ok(RoaringOperationLog::new(checkpoint).append_all(operations))
}

///|
/// Encode the current replayed state as a checked snapshot frame.
pub fn RoaringOperationLog::checkpoint_frame(
  self : RoaringOperationLog,
  format : CodecFormat,
) -> Result[BitmapFrame, RoaringError] {
  match self.replay() {
    Err(error) => Err(error)
    Ok(bitmap) =>
      match bitmap.frame(format) {
        Ok(frame) => Ok(frame)
        Err(_) => Err(RangeTooLarge(bitmap.cardinality()))
      }
  }
}
