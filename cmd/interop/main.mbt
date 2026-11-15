///|
/// Emit portable bytes as decimal lines for the independent CRoaring reader.
fn main {
  let bitmap = @roaring.UInt32Bitmap::new()
    .add_range(0UL, 10000UL)
    .unwrap()
    .add(2147483648U)
    .add(4294967295U)
  let bytes = bitmap.serialize_portable_compact()
  for byte in bytes {
    println(byte.to_int())
  }
}
