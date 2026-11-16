///|
/// Search filters, permissions and cohort analysis over unsigned IDs.
fn main {
  let a = @roaring.UInt32Bitmap::new().add(1U).add(2U).add(4294967295U)
  let b = @roaring.UInt32Bitmap::new().add(2U).add(3U).add(4294967295U)
  // Search: two postings lists determine which documents match both terms.
  let search = a.intersection(b)
  // Permissions: inherited grants are combined, then explicit denials removed.
  let inherited = @roaring.UInt32Bitmap::new().add(4U)
  let permission = a.union(inherited).difference(b)
  // Analytics: measure overlap between two cohorts.
  let cohort = a.intersection(b)
  if search.cardinality() != 2UL ||
    permission.cardinality() != 2UL ||
    cohort.cardinality() != 2UL {
    abort("unexpected scenario result")
  }
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
  let wrong = @roaring.UInt32Snapshot::new("search", 1UL, b)
  if wrong.apply(@roaring.decode_uint32_patch(wire, "search").unwrap()) is Ok(_) {
    abort("incorrect baseline was accepted")
  }
  let full_snapshot = b.serialize_portable_compact()
  let recovered = @roaring.decode_portable_uint32(full_snapshot).unwrap()
  if recovered.xor(b).cardinality() != 0UL {
    abort("full snapshot recovery failed")
  }
  println("checked update version: " + restored.generation().to_string())
  println("incorrect baseline rejected; portable snapshot recovered")
}
