///|
/// A replayable immutable bitmap operation.
pub(all) enum BitmapOperation {
  Add(Int)
  Remove(Int)
  AddRange(Int, Int)
  RemoveRange(Int, Int)
  AddAll(Array[Int])
  RemoveAll(Array[Int])
}

///|
/// Detach mutable batch payloads at the log's input and output boundaries.
fn BitmapOperation::owned_copy(self : BitmapOperation) -> BitmapOperation {
  match self {
    AddAll(values) => AddAll(values.copy())
    RemoveAll(values) => RemoveAll(values.copy())
    _ => self
  }
}

///|
/// A checkpoint plus ordered operations that have not yet been compacted.
pub struct RoaringOperationLog {
  checkpoint : RoaringBitmap
  operations : Array[BitmapOperation]
}

///|
/// Start an empty log from a known checkpoint.
pub fn RoaringOperationLog::new(
  checkpoint : RoaringBitmap,
) -> RoaringOperationLog {
  { checkpoint, operations: [], }
}

///|
/// Number of unapplied operations.
pub fn RoaringOperationLog::len(self : RoaringOperationLog) -> Int {
  self.operations.length()
}

///|
/// True when this log is already represented solely by its checkpoint.
pub fn RoaringOperationLog::is_compacted(self : RoaringOperationLog) -> Bool {
  self.operations.length() == 0
}

///|
/// Return the checkpoint without replaying pending operations.
pub fn RoaringOperationLog::checkpoint(
  self : RoaringOperationLog,
) -> RoaringBitmap {
  self.checkpoint
}

///|
/// Discard all pending operations and restore the original checkpoint state.
pub fn RoaringOperationLog::discard_pending(
  self : RoaringOperationLog,
) -> RoaringOperationLog {
  { checkpoint: self.checkpoint, operations: [], }
}

///|
/// Return the ordered operations as an isolated copy for audit sinks.
pub fn RoaringOperationLog::operations(
  self : RoaringOperationLog,
) -> Array[BitmapOperation] {
  self.operations.map(operation => operation.owned_copy())
}

///|
/// Append one operation, copying batch values without changing the checkpoint.
pub fn RoaringOperationLog::append(
  self : RoaringOperationLog,
  operation : BitmapOperation,
) -> RoaringOperationLog {
  let operations = self.operations.copy()
  operations.push(operation.owned_copy())
  { checkpoint: self.checkpoint, operations, }
}

///|
/// Append a batch while preserving its declared order.
pub fn RoaringOperationLog::append_all(
  self : RoaringOperationLog,
  additions : Array[BitmapOperation],
) -> RoaringOperationLog {
  let mut log = self
  for operation in additions {
    log = log.append(operation)
  }
  log
}

///|
/// Compute the checkpoint-to-current patch without changing this log.
pub fn RoaringOperationLog::pending_patch(
  self : RoaringOperationLog,
) -> Result[RoaringPatch, RoaringError] {
  match self.replay() {
    Ok(current) => Ok(self.checkpoint.diff_to(current))
    Err(error) => Err(error)
  }
}

///|
/// Replay all operations in order. Failure returns no partial bitmap.
pub fn RoaringOperationLog::replay(
  self : RoaringOperationLog,
) -> Result[RoaringBitmap, RoaringError] {
  let mut current = self.checkpoint
  for operation in self.operations {
    match operation.apply(current) {
      Ok(next) => current = next
      Err(error) => return Err(error)
    }
  }
  Ok(current)
}

///|
/// Materialize a new checkpoint and clear the replay queue.
pub fn RoaringOperationLog::compact(
  self : RoaringOperationLog,
) -> Result[RoaringOperationLog, RoaringError] {
  match self.replay() {
    Ok(checkpoint) => Ok({ checkpoint, operations: [], })
    Err(error) => Err(error)
  }
}

///|
/// Apply one operation to an immutable bitmap.
pub fn BitmapOperation::apply(
  self : BitmapOperation,
  bitmap : RoaringBitmap,
) -> Result[RoaringBitmap, RoaringError] {
  match self {
    Add(value) => bitmap.add(value)
    Remove(value) => Ok(bitmap.remove(value))
    AddRange(start, end) => bitmap.add_range(start, end)
    RemoveRange(start, end) => bitmap.remove_range(start, end)
    AddAll(values) => bitmap.add_all(values)
    RemoveAll(values) => bitmap.remove_all(values)
  }
}
