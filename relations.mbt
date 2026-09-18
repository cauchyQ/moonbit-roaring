///|
/// The mutually exclusive relation between two integer sets.
pub(all) enum SetRelation {
  Equal
  ProperSubset
  ProperSuperset
  Overlap
  Disjoint
}

///|
/// True when no member is shared by two bitmaps.
pub fn RoaringBitmap::is_disjoint(
  self : RoaringBitmap,
  other : RoaringBitmap,
) -> Bool {
  !self.intersects(other)
}

///|
/// True when `self` is contained in but not equal to `other`.
pub fn RoaringBitmap::is_proper_subset_of(
  self : RoaringBitmap,
  other : RoaringBitmap,
) -> Bool {
  self.is_subset_of(other) && self.cardinality() < other.cardinality()
}

///|
/// True when `self` contains but is not equal to `other`.
pub fn RoaringBitmap::is_proper_superset_of(
  self : RoaringBitmap,
  other : RoaringBitmap,
) -> Bool {
  other.is_proper_subset_of(self)
}

///|
/// Classify two sets using their set differences.
pub fn RoaringBitmap::relation_to(
  self : RoaringBitmap,
  other : RoaringBitmap,
) -> SetRelation {
  let left_only = self.difference(other)
  let right_only = other.difference(self)
  if left_only.is_empty() && right_only.is_empty() {
    Equal
  } else if left_only.is_empty() {
    ProperSubset
  } else if right_only.is_empty() {
    ProperSuperset
  } else if self.intersects(other) {
    Overlap
  } else {
    Disjoint
  }
}

///|
/// Number of values present in exactly one of the two bitmaps.
pub fn RoaringBitmap::symmetric_difference_cardinality(
  self : RoaringBitmap,
  other : RoaringBitmap,
) -> Int {
  self.xor(other).cardinality()
}

///|
/// Number of values shared by both bitmaps.
pub fn RoaringBitmap::intersection_cardinality(
  self : RoaringBitmap,
  other : RoaringBitmap,
) -> Int {
  self.intersection(other).cardinality()
}

///|
/// Number of distinct values present in either bitmap.
pub fn RoaringBitmap::union_cardinality(
  self : RoaringBitmap,
  other : RoaringBitmap,
) -> Int {
  self.union(other).cardinality()
}

///|
/// Number of values in `self` not present in `other`.
pub fn RoaringBitmap::difference_cardinality(
  self : RoaringBitmap,
  other : RoaringBitmap,
) -> Int {
  self.difference(other).cardinality()
}

///|
/// Return exact containment gaps: `(missing_from_self, missing_from_other)`.
pub fn RoaringBitmap::containment_gaps(
  self : RoaringBitmap,
  other : RoaringBitmap,
) -> (Int, Int) {
  (other.difference(self).cardinality(), self.difference(other).cardinality())
}

///|
/// Return the shared fraction as exact `(shared, smaller_set_size)` parts.
/// An empty smaller set has denominator zero instead of an invented ratio.
pub fn RoaringBitmap::overlap_coefficient_parts(
  self : RoaringBitmap,
  other : RoaringBitmap,
) -> (Int, Int) {
  let left = self.cardinality()
  let right = other.cardinality()
  let denominator = if left < right { left } else { right }
  (self.intersection_cardinality(other), denominator)
}
