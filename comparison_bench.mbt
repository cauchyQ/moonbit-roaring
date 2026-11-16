///|
/// Compare identical input sets with xcc-ordinary/moonbit-roaring 0.1.0.
test (b : @bench.T) {
  for shape in 0..<3 {
    let label = ["sequential", "sparse", "dense_even"][shape]
    let values : Array[UInt32] = []
    let filter_values : Array[UInt32] = []
    let mut ours = UInt32Bitmap::new()
    let mut our_filter = UInt32Bitmap::new()
    for i in 0..<6000 {
      let value = if shape == 0 {
        i
      } else if shape == 1 {
        i * 100003
      } else {
        i * 2
      }
      let id = value.reinterpret_as_uint()
      values.push(id)
      ours = ours.add(id)
      if i % 3 == 0 {
        filter_values.push(id)
        our_filter = our_filter.add(id)
      }
    }
    let theirs = @portable.RoaringBitmap::from_array(values)
    let their_filter = @portable.RoaringBitmap::from_array(filter_values)
    let ours_intersect = ours.intersection(our_filter)
    let their_intersect = theirs.intersect(their_filter)
    assert_eq(ours_intersect.cardinality(), their_intersect.size().to_uint64())
    for i in 0..<filter_values.length() {
      assert_eq(ours_intersect.select(i.to_uint64()), Some(filter_values[i]))
      assert_eq(their_intersect.select(i), Some(filter_values[i]))
    }
    let ours_bytes = ours.serialize_portable_compact()
    let theirs_bytes = theirs.serialize()
    let imported = decode_portable_uint32(theirs_bytes).unwrap()
    assert_eq(imported.xor(ours).cardinality(), 0UL)
    let reverse = @portable.RoaringBitmap::deserialize(ours_bytes).unwrap()
    assert_eq(reverse.to_array(), values)
    println(
      label +
      " ours_bytes=" +
      ours_bytes.length().to_string() +
      " other_bytes=" +
      theirs_bytes.length().to_string(),
    )
    b.bench(name=label + "_ours_intersection", fn() {
      b.keep(ours.intersection(our_filter).cardinality())
    })
    b.bench(name=label + "_other_intersection", fn() {
      b.keep(theirs.intersect(their_filter).size())
    })
    b.bench(name=label + "_ours_encode", fn() {
      b.keep(ours.serialize_portable_compact().length())
    })
    b.bench(name=label + "_other_encode", fn() {
      b.keep(theirs.serialize().length())
    })
  }
}
