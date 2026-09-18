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
  { checkpoint, operations: [] }
}

///|
/// Number of unapplied operations.
pub fn RoaringOperationLog::len(self : RoaringOperationLog) -> Int {
  self.operations.length()
}

///|
/// Append one operation without changing the checkpoint.
pub fn RoaringOperationLog::append(
  self : RoaringOperationLog,
  operation : BitmapOperation,
) -> RoaringOperationLog {
  let operations = self.operations.copy()
  operations.push(operation)
  { checkpoint: self.checkpoint, operations }
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
    Ok(checkpoint) => Ok({ checkpoint, operations: [] })
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
