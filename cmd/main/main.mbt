///|
/// Build two small inverted indexes and intersect them like a search filter.
fn main {
  let tagged_rust = @roaring.RoaringBitmap::from_array([1, 2, 3, 10, 70_000]).unwrap()
  let tagged_database = @roaring.RoaringBitmap::from_array([2, 3, 8, 70_000]).unwrap()
  let matches = tagged_rust.intersection(tagged_database)
  println(
    "first matching document id=" + matches.select(0).unwrap().to_string(),
  )
  println("count=" + matches.cardinality().to_string())
}
