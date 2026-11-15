///|
test (b : @bench.T) {
  for scenario in 0..<3 {
    let name = ["search", "permissions", "analytics"][scenario]
    let base_bitmap = UInt32Bitmap::new()
      .add_range(0UL, 10000UL)
      .unwrap()
      .add(4294967295U)
    let target_bitmap = base_bitmap
      .remove_range(100UL, 110UL)
      .unwrap()
      .add_range(20000UL, 20010UL)
      .unwrap()
    let base = UInt32Snapshot::new(name, 1UL, base_bitmap)
    let target = UInt32Snapshot::new(name, 2UL, target_bitmap)
    let filter = UInt32Bitmap::new().add_range(0UL, 5000UL).unwrap()
    let patch = base.diff_to(target).unwrap().serialize()
    let full = target_bitmap.serialize_portable_compact()
    let reconstructed = base
      .apply(decode_uint32_patch(patch, name).unwrap())
      .unwrap()
      .bitmap()
    assert_eq(reconstructed.xor(target_bitmap).cardinality(), 0UL)
    b.bench(name=name + "_full_refresh_query", fn() {
      let bitmap = decode_portable_uint32(full).unwrap()
      let result = if scenario == 1 {
        bitmap.difference(filter)
      } else {
        bitmap.intersection(filter)
      }
      b.keep(result.cardinality())
    })
    b.bench(name=name + "_delta_refresh_query", fn() {
      let decoded = decode_uint32_patch(patch, name).unwrap()
      let bitmap = base.apply(decoded).unwrap().bitmap()
      let result = if scenario == 1 {
        bitmap.difference(filter)
      } else {
        bitmap.intersection(filter)
      }
      b.keep(result.cardinality())
    })
    b.bench(name=name + "_produce_full", fn() {
      b.keep(target_bitmap.serialize_portable_compact().length())
    })
    b.bench(name=name + "_produce_delta_with_hashes", fn() {
      b.keep(base.diff_to(target).unwrap().serialize().length())
    })
    println(
      name +
      " full_bytes=" +
      full.length().to_string() +
      " delta_bytes=" +
      patch.length().to_string(),
    )
  }
}
