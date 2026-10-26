///|
/// One numeric label and the bitmap indexed by that label.
pub(all) struct BitmapEntry {
  key : Int
  bitmap : RoaringBitmap
}

///|
/// Small immutable catalog for faceted search and rule evaluation.
pub struct BitmapCatalog {
  entries : Array[BitmapEntry]
}

///|
/// Boolean expression evaluated against a catalog and an explicit universe.
pub(all) enum CatalogQuery {
  Key(Int)
  Any(Array[CatalogQuery])
  All(Array[CatalogQuery])
  Not(CatalogQuery)
  AtLeast(Int, Array[CatalogQuery])
}

///|
pub fn BitmapCatalog::new() -> BitmapCatalog {
  { entries: [], }
}

///|
pub fn BitmapCatalog::get(self : BitmapCatalog, key : Int) -> RoaringBitmap? {
  for entry in self.entries {
    if entry.key == key {
      return Some(entry.bitmap)
    }
  }
  None
}

///|
pub fn BitmapCatalog::upsert(
  self : BitmapCatalog,
  key : Int,
  bitmap : RoaringBitmap,
) -> BitmapCatalog {
  let entries : Array[BitmapEntry] = []
  let mut replaced = false
  for entry in self.entries {
    if entry.key == key {
      entries.push({ key, bitmap, })
      replaced = true
    } else {
      entries.push(entry)
    }
  }
  if !replaced {
    entries.push({ key, bitmap, })
    entries.sort_by((a, b) => a.key.compare(b.key))
  }
  { entries, }
}

///|
pub fn BitmapCatalog::remove(self : BitmapCatalog, key : Int) -> BitmapCatalog {
  { entries: self.entries.filter(entry => entry.key != key), }
}

///|
/// Keys in deterministic ascending order.
pub fn BitmapCatalog::keys(self : BitmapCatalog) -> Array[Int] {
  let output : Array[Int] = []
  for entry in self.entries {
    output.push(entry.key)
  }
  output
}

///|
/// Number of indexed labels.
pub fn BitmapCatalog::len(self : BitmapCatalog) -> Int {
  self.entries.length()
}

///|
/// Static query metadata available without evaluating bitmap operands.
pub(all) struct CatalogQueryStats {
  nodes : Int
  depth : Int
  key_references : Int
}

///|
/// Inspect the structural shape of a catalog query.
pub fn CatalogQuery::stats(self : CatalogQuery) -> CatalogQueryStats {
  match self {
    Key(_) => { nodes: 1, depth: 1, key_references: 1, }
    Not(child) => {
      let stats = child.stats()
      {
        nodes: stats.nodes + 1,
        depth: stats.depth + 1,
        key_references: stats.key_references,
      }
    }
    Any(children) | All(children) | AtLeast(_, children) => {
      let mut nodes = 1
      let mut depth = 1
      let mut refs = 0
      for child in children {
        let stats = child.stats()
        nodes += stats.nodes
        refs += stats.key_references
        if stats.depth + 1 > depth {
          depth = stats.depth + 1
        }
      }
      { nodes, depth, key_references: refs, }
    }
  }
}

///|
/// Collect keys in deterministic depth-first order, retaining repeats.
pub fn CatalogQuery::referenced_keys(self : CatalogQuery) -> Array[Int] {
  match self {
    Key(key) => [key]
    Not(child) => child.referenced_keys()
    Any(children) | All(children) | AtLeast(_, children) => {
      let output : Array[Int] = []
      for child in children {
        for key in child.referenced_keys() {
          output.push(key)
        }
      }
      output
    }
  }
}

///|
/// Evaluation output paired with catalog keys that were absent at lookup time.
pub(all) struct CatalogQueryResult {
  bitmap : RoaringBitmap
  missing_keys : Array[Int]
}

///|
/// Evaluate a query and report missing keys separately from an empty bitmap.
pub fn BitmapCatalog::evaluate_traced(
  self : BitmapCatalog,
  query : CatalogQuery,
  universe : RoaringBitmap,
) -> CatalogQueryResult {
  let missing : Array[Int] = []
  for key in query.referenced_keys() {
    if self.get(key) is None && !missing.contains(key) {
      missing.push(key)
    }
  }
  { bitmap: self.evaluate(query, universe), missing_keys: missing, }
}

///|
pub fn BitmapCatalog::evaluate(
  self : BitmapCatalog,
  query : CatalogQuery,
  universe : RoaringBitmap,
) -> RoaringBitmap {
  match query {
    Key(key) => self.get(key).unwrap_or(RoaringBitmap::new())
    Any(children) => {
      let mut out = RoaringBitmap::new()
      for child in children {
        out = out.union(self.evaluate(child, universe))
      }
      out
    }
    All(children) => {
      let mut out = universe
      for child in children {
        out = out.intersection(self.evaluate(child, universe))
      }
      out
    }
    Not(child) => universe.difference(self.evaluate(child, universe))
    AtLeast(threshold, children) => {
      if threshold <= 0 {
        return universe
      }
      let values : Array[Int] = []
      for child in children {
        for value in self.evaluate(child, universe).to_array() {
          values.push(value)
        }
      }
      values.sort()
      let out : Array[Int] = []
      let mut index = 0
      while index < values.length() {
        let value = values[index]
        let mut count = 0
        while index < values.length() && values[index] == value {
          count += 1
          index += 1
        }
        if count >= threshold {
          out.push(value)
        }
      }
      from_sorted(out)
    }
  }
}
