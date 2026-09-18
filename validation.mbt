///|
/// Structural invariant failures reported by `validate`.
pub(all) enum ValidationError {
  UnsortedBlockKey(Int, Int)
  EmptyBlock(Int)
  InvalidLowValue(Int, Int)
  UnsortedLowValue(Int, Int, Int)
  BitmapCardinalityMismatch(Int, Int)
  RunCardinalityMismatch(Int, Int)
  InvalidRun(Int, Int, Int)
}

///|
/// Verify representation invariants without changing this bitmap.
/// This is useful at trust boundaries and in differential tests.
pub fn RoaringBitmap::validate(
  self : RoaringBitmap,
) -> Result[Unit, ValidationError] {
  let mut previous_key = -1
  for block in self.blocks {
    if block.key <= previous_key {
      return Err(UnsortedBlockKey(previous_key, block.key))
    }
    previous_key = block.key
    match block.container {
      ArrayContainer(values) => {
        if values.length() == 0 {
          return Err(EmptyBlock(block.key))
        }
        let mut previous = -1
        for low in values {
          if low < 0 || low >= block_size {
            return Err(InvalidLowValue(block.key, low))
          }
          if low <= previous {
            return Err(UnsortedLowValue(block.key, previous, low))
          }
          previous = low
        }
      }
      BitmapContainer(words, declared) => {
        let mut actual = 0
        for word in words {
          actual += count_word_bits(word)
        }
        if actual == 0 {
          return Err(EmptyBlock(block.key))
        }
        if actual != declared {
          return Err(BitmapCardinalityMismatch(declared, actual))
        }
      }
      RunContainer(runs, declared) => {
        if runs.length() == 0 {
          return Err(EmptyBlock(block.key))
        }
        let mut actual = 0
        let mut previous_end = -1
        for run in runs {
          if run.start < 0 ||
            run.end < run.start ||
            run.end >= block_size ||
            run.start <= previous_end + 1 {
            return Err(InvalidRun(block.key, run.start, run.end))
          }
          actual += run.end - run.start + 1
          previous_end = run.end
        }
        if actual != declared {
          return Err(RunCardinalityMismatch(declared, actual))
        }
      }
    }
  }
  Ok(())
}
