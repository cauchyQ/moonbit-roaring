///|
/// Invalid positions or failed operations in a requested history.
pub(all) enum JournalRangeError {
  InvalidIndex(Int, Int)
  OperationFailed(Int, RoaringError)
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
    Ok(self.operations[index].owned_copy())
  }
}

///|
/// Replay exactly the first `count` operations, reporting a zero-based failure index.
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
      Err(error) => return Err(OperationFailed(index, error))
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
  let checkpoint = match self.replay_prefix(count) {
    Ok(bitmap) => bitmap
    Err(error) => return Err(error)
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
  // Stored payloads are already owned and never mutated; only queues are split.
  let prefix : RoaringOperationLog = {
    checkpoint: self.checkpoint,
    operations: prefix_operations,
  }
  let suffix : RoaringOperationLog = {
    checkpoint,
    operations: suffix_operations,
  }
  Ok((prefix, suffix))
}

///|
/// Return cumulative cardinalities, or the first failure with a zero-based index.
pub fn RoaringOperationLog::cardinality_history(
  self : RoaringOperationLog,
) -> Result[Array[Int], JournalRangeError] {
  let output : Array[Int] = [self.checkpoint.cardinality()]
  let mut current = self.checkpoint
  for index in 0..<self.operations.length() {
    let operation = self.operations[index]
    match operation.apply(current) {
      Ok(next) => {
        current = next
        output.push(current.cardinality())
      }
      Err(error) => return Err(OperationFailed(index, error))
    }
  }
  Ok(output)
}
