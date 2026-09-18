///|
/// Exact comparison facts for two bitmaps, suitable for reporting decisions.
pub(all) struct BitmapComparison {
  relation : SetRelation
  left_cardinality : Int
  right_cardinality : Int
  common_cardinality : Int
  left_only_cardinality : Int
  right_only_cardinality : Int
  union_cardinality : Int
}

///|
/// Compare two bitmaps once and retain all basic cardinality facts.
pub fn compare_bitmaps(
  left : RoaringBitmap,
  right : RoaringBitmap,
) -> BitmapComparison {
  let common = left.intersection_cardinality(right)
  let left_cardinality = left.cardinality()
  let right_cardinality = right.cardinality()
  let left_only = left_cardinality - common
  let right_only = right_cardinality - common
  {
    relation: left.relation_to(right),
    left_cardinality,
    right_cardinality,
    common_cardinality: common,
    left_only_cardinality: left_only,
    right_only_cardinality: right_only,
    union_cardinality: common + left_only + right_only,
  }
}

///|
/// Return exact precision parts when `actual` is compared to `expected`.
pub fn precision_parts(
  actual : RoaringBitmap,
  expected : RoaringBitmap,
) -> (Int, Int) {
  (actual.intersection_cardinality(expected), actual.cardinality())
}

///|
/// Return exact recall parts when `actual` is compared to `expected`.
pub fn recall_parts(
  actual : RoaringBitmap,
  expected : RoaringBitmap,
) -> (Int, Int) {
  (actual.intersection_cardinality(expected), expected.cardinality())
}

///|
/// Return exact F1 components `(two_times_common, actual_plus_expected)`.
pub fn f1_parts(actual : RoaringBitmap, expected : RoaringBitmap) -> (Int, Int) {
  (
    2 * actual.intersection_cardinality(expected),
    actual.cardinality() + expected.cardinality(),
  )
}

///|
/// True when equality holds after restricting both bitmaps to an allowed universe.
pub fn equal_within(
  left : RoaringBitmap,
  right : RoaringBitmap,
  universe : RoaringBitmap,
) -> Bool {
  left.intersection(universe).relation_to(right.intersection(universe)) is Equal
}
