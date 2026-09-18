///|
/// Invalid operation-log position requests.
pub(all) enum JournalRangeError {
  InvalidIndex(Int, Int)
}

///|
/// Return one operation by zero-based index.
pub fn RoaringOperationLog::operation_at(
  self : RoaringOperationLog,
  index : Int,
) -> Result[BitmapOperation, JournalRangeError] {
  if index < 0 || index >= self.operations.length() {
    Err(InvalidIndex(index, self.operations.length()))
  } else {
    Ok(self.operations[index])
  }
}

///|
/// Replay exactly the first `count` operations from this log checkpoint.
pub fn RoaringOperationLog::replay_prefix(
  self : RoaringOperationLog,
  count : Int,
) -> Result[RoaringBitmap, JournalRangeError] {
  if count < 0 || count > self.operations.length() {
    return Err(InvalidIndex(count, self.operations.length()))
  }
  let mut current = self.checkpoint
  for index in 0..<count {
    match self.operations[index].apply(current) {
      Ok(next) => current = next
      Err(_) => return Ok(self.checkpoint)
    }
  }
  Ok(current)
}

///|
/// Split a log into its retained prefix and a suffix rebased on the prefix state.
pub fn RoaringOperationLog::split_at(
  self : RoaringOperationLog,
  count : Int,
) -> Result[(RoaringOperationLog, RoaringOperationLog), JournalRangeError] {
  if count < 0 || count > self.operations.length() {
    return Err(InvalidIndex(count, self.operations.length()))
  }
  let prefix_operations : Array[BitmapOperation] = []
  let suffix_operations : Array[BitmapOperation] = []
  for index in 0..<self.operations.length() {
    if index < count {
      prefix_operations.push(self.operations[index])
    } else {
      suffix_operations.push(self.operations[index])
    }
  }
  let prefix = RoaringOperationLog::new(self.checkpoint).append_all(
    prefix_operations,
  )
  let checkpoint = match prefix.replay() {
    Ok(bitmap) => bitmap
    Err(_) => self.checkpoint
  }
  Ok(
    (prefix, RoaringOperationLog::new(checkpoint).append_all(suffix_operations)),
  )
}

///|
/// Return cumulative cardinalities after each replayed operation, including the checkpoint.
pub fn RoaringOperationLog::cardinality_history(
  self : RoaringOperationLog,
) -> Array[Int] {
  let output : Array[Int] = [self.checkpoint.cardinality()]
  let mut current = self.checkpoint
  for operation in self.operations {
    match operation.apply(current) {
      Ok(next) => {
        current = next
        output.push(current.cardinality())
      }
      Err(_) => output.push(current.cardinality())
    }
  }
  output
}
