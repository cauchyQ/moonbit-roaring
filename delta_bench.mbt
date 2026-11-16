///|
test (b : @bench.T) {
  let mut bitmap = UInt32Bitmap::new()
  for i in 0..<10000 {
    bitmap = bitmap.add((i * 100003).reinterpret_as_uint())
  }
  let base = UInt32Snapshot::new("sparse", 1UL, bitmap)
  for count in [10, 100, 1000] {
    let mut target_bitmap = bitmap
    for i in 0..<count {
      target_bitmap = target_bitmap.remove((i * 100003).reinterpret_as_uint())
    }
    let target = UInt32Snapshot::new("sparse", 2UL, target_bitmap)
    let patch = base.diff_to(target).unwrap().serialize()
    let full = target_bitmap.serialize_portable_compact()
    let restored = base
      .apply(decode_uint32_patch(patch, "sparse").unwrap())
      .unwrap()
    assert_eq(restored.bitmap().xor(target_bitmap).cardinality(), 0UL)
    println(
      "removed=" +
      count.to_string() +
      " full_bytes=" +
      full.length().to_string() +
      " delta_bytes=" +
      patch.length().to_string(),
    )
    let label = count.to_string()
    b.bench(name="full_encode_" + label, fn() {
      b.keep(target_bitmap.serialize_portable_compact().length())
    })
    b.bench(name="delta_encode_" + label, fn() {
      b.keep(base.diff_to(target).unwrap().serialize().length())
    })
    b.bench(name="full_decode_" + label, fn() {
      b.keep(decode_portable_uint32(full).unwrap().cardinality())
    })
    b.bench(name="delta_apply_" + label, fn() {
      b.keep(
        base
        .apply(decode_uint32_patch(patch, "sparse").unwrap())
        .unwrap()
        .bitmap()
        .cardinality(),
      )
    })
  }
}
