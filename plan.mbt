///|
/// A composable immutable set-algebra execution plan.
pub(all) enum BitmapPlan {
  Source(RoaringBitmap)
  Union(BitmapPlan, BitmapPlan)
  Intersection(BitmapPlan, BitmapPlan)
  Difference(BitmapPlan, BitmapPlan)
  Xor(BitmapPlan, BitmapPlan)
  Take(BitmapPlan, Int)
  Drop(BitmapPlan, Int)
}

///|
pub fn BitmapPlan::evaluate(self : BitmapPlan) -> RoaringBitmap {
  match self {
    Source(bitmap) => bitmap
    Union(left, right) => left.evaluate().union(right.evaluate())
    Intersection(left, right) => left.evaluate().intersection(right.evaluate())
    Difference(left, right) => left.evaluate().difference(right.evaluate())
    Xor(left, right) => left.evaluate().xor(right.evaluate())
    Take(input, count) => input.evaluate().take(count)
    Drop(input, count) => input.evaluate().drop(count)
  }
}

///|
pub fn BitmapPlan::estimated_cardinality(self : BitmapPlan) -> Int {
  self.evaluate().cardinality()
}

///|
/// Static shape information for a plan before execution.
pub(all) struct BitmapPlanStats {
  nodes : Int
  depth : Int
  sources : Int
}

///|
/// Count nodes, depth, and source leaves without materializing a bitmap.
pub fn BitmapPlan::stats(self : BitmapPlan) -> BitmapPlanStats {
  match self {
    Source(_) => { nodes: 1, depth: 1, sources: 1 }
    Take(input, _) | Drop(input, _) => {
      let child = input.stats()
      { nodes: child.nodes + 1, depth: child.depth + 1, sources: child.sources }
    }
    Union(left, right)
    | Intersection(left, right)
    | Difference(left, right)
    | Xor(left, right) => {
      let a = left.stats()
      let b = right.stats()
      {
        nodes: a.nodes + b.nodes + 1,
        depth: (if a.depth > b.depth { a.depth } else { b.depth }) + 1,
        sources: a.sources + b.sources,
      }
    }
  }
}

///|
/// Render a stable compact prefix description for diagnostics.
pub fn BitmapPlan::describe(self : BitmapPlan) -> String {
  match self {
    Source(bitmap) => "source(" + bitmap.cardinality().to_string() + ")"
    Union(left, right) =>
      "union(" + left.describe() + "," + right.describe() + ")"
    Intersection(left, right) =>
      "intersection(" + left.describe() + "," + right.describe() + ")"
    Difference(left, right) =>
      "difference(" + left.describe() + "," + right.describe() + ")"
    Xor(left, right) => "xor(" + left.describe() + "," + right.describe() + ")"
    Take(input, count) =>
      "take(" + count.to_string() + "," + input.describe() + ")"
    Drop(input, count) =>
      "drop(" + count.to_string() + "," + input.describe() + ")"
  }
}
