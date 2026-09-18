///|
/// Read-only execution information for a catalog query.
pub(all) struct QueryExecutionTrace {
  result : RoaringBitmap
  nodes : Int
  depth : Int
  requested_keys : Array[Int]
  resolved_keys : Array[Int]
  missing_keys : Array[Int]
  result_cardinality : Int
}

///|
/// Evaluate a catalog query and record its observable planning facts.
pub fn BitmapCatalog::execute_with_trace(
  self : BitmapCatalog,
  query : CatalogQuery,
  universe : RoaringBitmap,
) -> QueryExecutionTrace {
  let query_stats = query.stats()
  let requested = query.referenced_keys()
  let resolved : Array[Int] = []
  let missing : Array[Int] = []
  for key in requested {
    match self.get(key) {
      Some(_) => if !resolved.contains(key) { resolved.push(key) }
      None => if !missing.contains(key) { missing.push(key) }
    }
  }
  let result = self.evaluate(query, universe)
  {
    result,
    nodes: query_stats.nodes,
    depth: query_stats.depth,
    requested_keys: requested,
    resolved_keys: resolved,
    missing_keys: missing,
    result_cardinality: result.cardinality(),
  }
}

///|
/// Return a conservative result upper bound before evaluating a query.
/// The bound is the universe cardinality for any expression containing Not.
pub fn CatalogQuery::result_upper_bound(
  self : CatalogQuery,
  catalog : BitmapCatalog,
  universe : RoaringBitmap,
) -> Int {
  match self {
    Key(key) => catalog.get(key).unwrap_or(RoaringBitmap::new()).cardinality()
    Not(_) => universe.cardinality()
    Any(children) => {
      let mut total = 0
      for child in children {
        let bound = child.result_upper_bound(catalog, universe)
        if total > universe.cardinality() - bound {
          return universe.cardinality()
        }
        total += bound
      }
      total
    }
    All(children) => {
      let mut bound = universe.cardinality()
      for child in children {
        let child_bound = child.result_upper_bound(catalog, universe)
        if child_bound < bound {
          bound = child_bound
        }
      }
      bound
    }
    AtLeast(threshold, children) =>
      if threshold <= 0 {
        universe.cardinality()
      } else if threshold > children.length() {
        0
      } else {
        let mut total = 0
        for child in children {
          let bound = child.result_upper_bound(catalog, universe)
          if total > universe.cardinality() - bound {
            return universe.cardinality()
          }
          total += bound
        }
        total
      }
  }
}
