///|
/// Serialize an existing non-negative Int bitmap using Roaring portable format.
pub fn RoaringBitmap::serialize_portable(self : RoaringBitmap) -> Bytes {
  let values : Array[UInt32] = []
  for value in self.to_array() {
    values.push(value.reinterpret_as_uint())
  }
  @portable.RoaringBitmap::from_array(values).serialize()
}

///|
/// Import a portable bitmap when every member fits the current Int API.
pub fn decode_portable(bytes : Bytes) -> Result[RoaringBitmap, String] {
  let bitmap = match @portable.RoaringBitmap::deserialize(bytes) {
    Ok(value) => value
    Err(error) => return Err(error.to_string())
  }
  let values : Array[Int32] = []
  for value in bitmap.to_array() {
    if value > 2_147_483_647U {
      return Err("portable bitmap contains a value outside the Int API")
    }
    values.push(value.reinterpret_as_int())
  }
  match RoaringBitmap::from_array(values) {
    Ok(value) => Ok(value)
    Err(_) => Err("invalid bitmap value")
  }
}
