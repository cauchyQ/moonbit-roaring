///|
/// Search filters, permissions and cohort analysis over unsigned IDs.
fn main {
  let a = @roaring.UInt32Bitmap::new().add(1U).add(2U).add(4294967295U)
  let b = @roaring.UInt32Bitmap::new().add(2U).add(3U).add(4294967295U)
  let search = a.intersection(b)
  let permission = a.difference(b)
  let cohort = a.intersection(b)
  println("search matches: " + search.cardinality().to_string())
  println("allowed resources: " + permission.cardinality().to_string())
  println("cohort overlap: " + cohort.cardinality().to_string())
  let base = @roaring.UInt32Snapshot::new("search", 1UL, a)
  let next = @roaring.UInt32Snapshot::new("search", 2UL, b)
  let wire = base.diff_to(next).unwrap().serialize()
  let restored = base
    .apply(@roaring.decode_uint32_patch(wire, "search").unwrap())
    .unwrap()
  if restored.bitmap().xor(b).cardinality() != 0UL {
    abort("snapshot reconstruction failed")
  }
  println("checked update version: " + restored.generation().to_string())
}
