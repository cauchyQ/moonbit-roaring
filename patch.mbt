///|
/// An immutable delta that transforms one bitmap into another.
pub struct RoaringPatch {
  additions : RoaringBitmap
  removals : RoaringBitmap
}

///|
/// Compute the exact additions and removals needed to reach `target`.
pub fn RoaringBitmap::diff_to(
  self : RoaringBitmap,
  target : RoaringBitmap,
) -> RoaringPatch {
  { additions: target.difference(self), removals: self.difference(target), }
}

///|
/// Apply this patch. Removals are performed before additions.
pub fn RoaringPatch::apply(
  self : RoaringPatch,
  base : RoaringBitmap,
) -> RoaringBitmap {
  base.difference(self.removals).union(self.additions)
}

///|
/// Return a patch that reverses this patch when applied to its target state.
pub fn RoaringPatch::invert(self : RoaringPatch) -> RoaringPatch {
  { additions: self.removals, removals: self.additions, }
}

///|
/// Values touched by this patch, regardless of direction.
pub fn RoaringPatch::touched(self : RoaringPatch) -> RoaringBitmap {
  self.additions.union(self.removals)
}

///|
/// Number of values added by this patch.
pub fn RoaringPatch::added_cardinality(self : RoaringPatch) -> Int {
  self.additions.cardinality()
}

///|
/// Number of values removed by this patch.
pub fn RoaringPatch::removed_cardinality(self : RoaringPatch) -> Int {
  self.removals.cardinality()
}

///|
/// True when the patch makes no change.
pub fn RoaringPatch::is_empty(self : RoaringPatch) -> Bool {
  self.additions.is_empty() && self.removals.is_empty()
}
