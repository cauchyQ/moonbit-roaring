///|
test "journal snapshots batch input before caller mutation" {
  let checkpoint = @moonbit-roaring.RoaringBitmap::from_array([1, 2, 3]).unwrap()
  for adding in [true, false] {
    for batched in [true, false] {
      let values = if adding { [4, 5] } else { [1, 2] }
      let operation : @moonbit-roaring.BitmapOperation = if adding {
        AddAll(values)
      } else {
        RemoveAll(values)
      }
      let additions = [operation]
      let empty = @moonbit-roaring.RoaringOperationLog::new(checkpoint)
      let log = if batched {
        empty.append_all(additions)
      } else {
        empty.append(operation)
      }
      let expected = operation.apply(checkpoint).unwrap().to_array()
      let encoded = log.encode_words()
      values[0] = 99
      values.clear()
      values.push(99)
      additions[0] = Add(99)
      additions.clear()
      assert_eq(log.replay().unwrap().to_array(), expected)
      assert_eq(log.encode_words(), encoded)
      assert_eq(log.checkpoint().to_array(), [1, 2, 3])
      assert_true(empty.is_compacted())
    }
  }
}

///|
test "journal read APIs and split branches cannot expose mutable history" {
  let checkpoint = @moonbit-roaring.RoaringBitmap::from_array([1, 2, 3]).unwrap()
  let batches : Array[@moonbit-roaring.BitmapOperation] = [
    AddAll([4, 5]),
    RemoveAll([1, 2]),
  ]
  for operation in batches {
    let log = @moonbit-roaring.RoaringOperationLog::new(checkpoint)
      .append(operation)
      .append(Add(10))
    let branch = log.append(Add(20))
    let (prefix, suffix) = log.split_at(1).unwrap()
    let (_, rebased) = log.split_at(0).unwrap()
    let expected = log.replay().unwrap().to_array()
    let branch_expected = branch.replay().unwrap().to_array()
    let encoded = log.encode_words()
    let exported = log.operations()
    for
      op in [
        exported[0],
        log.operation_at(0).unwrap(),
        branch.operation_at(0).unwrap(),
        prefix.operation_at(0).unwrap(),
        rebased.operation_at(0).unwrap(),
      ] {
      match op {
        AddAll(values) | RemoveAll(values) => {
          values[0] = 99
          values.clear()
          values.push(99)
        }
        _ => fail("expected a batch operation")
      }
    }
    exported[0] = Add(99)
    exported.clear()
    assert_eq(log.encode_words(), encoded)
    assert_eq(log.replay().unwrap().to_array(), expected)
    assert_eq(branch.replay().unwrap().to_array(), branch_expected)
    assert_eq(suffix.replay().unwrap().to_array(), expected)
    assert_eq(rebased.replay().unwrap().to_array(), expected)
    assert_eq(
      prefix.replay().unwrap().to_array(),
      suffix.checkpoint().to_array(),
    )
  }
}

///|
test "failed prefixes preserve the failing position and cannot seed split checkpoints" {
  let checkpoint = @moonbit-roaring.RoaringBitmap::from_array([1]).unwrap()
  for failed_index in 0..<3 {
    let operations : Array[@moonbit-roaring.BitmapOperation] = [
      Add(10),
      Add(20),
      Add(30),
    ]
    operations[failed_index] = Add(-1)
    let log = @moonbit-roaring.RoaringOperationLog::new(checkpoint).append_all(
      operations,
    )
    let encoded = log.encode_words()
    assert_true(log.replay() is Err(NegativeValue(-1)))
    assert_true(log.compact() is Err(NegativeValue(-1)))
    assert_true(log.pending_patch() is Err(NegativeValue(-1)))
    assert_true(log.checkpoint_frame(RunWords) is Err(NegativeValue(-1)))
    for count in 0..<4 {
      if count <= failed_index {
        let expected = [1]
        for index in 0..<count {
          expected.push((index + 1) * 10)
        }
        assert_eq(log.replay_prefix(count).unwrap().to_array(), expected)
        let (prefix, suffix) = log.split_at(count).unwrap()
        assert_eq(prefix.replay().unwrap().to_array(), expected)
        assert_eq(suffix.checkpoint().to_array(), expected)
        assert_true(suffix.replay() is Err(NegativeValue(-1)))
      } else {
        match log.replay_prefix(count) {
          Err(OperationFailed(index, NegativeValue(-1))) =>
            assert_eq(index, failed_index)
          _ => fail("failed prefix returned success or lost its cause")
        }
        match log.split_at(count) {
          Err(OperationFailed(index, NegativeValue(-1))) =>
            assert_eq(index, failed_index)
          _ => fail("failed prefix produced a split checkpoint")
        }
      }
    }
    match log.cardinality_history() {
      Err(OperationFailed(index, NegativeValue(-1))) =>
        assert_eq(index, failed_index)
      _ => fail("failed operation produced a successful cardinality history")
    }
    assert_eq(log.encode_words(), encoded)
    assert_eq(log.checkpoint().to_array(), [1])
    assert_eq(checkpoint.to_array(), [1])
  }
}

///|
test "history errors retain invalid range and batch causes" {
  let empty = @moonbit-roaring.RoaringOperationLog::new(
    @moonbit-roaring.RoaringBitmap::new(),
  )
  let bad_range = empty.append(AddRange(3, 2))
  assert_true(
    bad_range.replay_prefix(1) is Err(OperationFailed(0, InvalidRange(3, 2))),
  )
  assert_true(
    bad_range.split_at(1) is Err(OperationFailed(0, InvalidRange(3, 2))),
  )
  assert_true(
    bad_range.cardinality_history()
    is Err(OperationFailed(0, InvalidRange(3, 2))),
  )
  let batches : Array[@moonbit-roaring.BitmapOperation] = [
    AddAll([1, -1]),
    RemoveAll([1, -1]),
  ]
  for operation in batches {
    let log = empty.append(operation)
    assert_true(
      log.replay_prefix(1) is Err(OperationFailed(0, NegativeValue(-1))),
    )
    assert_true(log.split_at(1) is Err(OperationFailed(0, NegativeValue(-1))))
    assert_true(
      log.cardinality_history() is Err(OperationFailed(0, NegativeValue(-1))),
    )
  }
  assert_true(empty.replay_prefix(-1) is Err(InvalidIndex(-1, 0)))
  assert_true(empty.replay_prefix(1) is Err(InvalidIndex(1, 0)))
  assert_true(empty.split_at(-1) is Err(InvalidIndex(-1, 0)))
  assert_true(empty.split_at(1) is Err(InvalidIndex(1, 0)))
  assert_eq(empty.cardinality_history().unwrap(), [0])
}

///|
test "valid journal splits and codec round trips preserve the final state" {
  let checkpoint = @moonbit-roaring.RoaringBitmap::from_array([1, 4]).unwrap()
  let log = @moonbit-roaring.RoaringOperationLog::new(checkpoint).append_all([
    AddAll([2, 3]),
    RemoveAll([1, 99]),
    AddRange(6, 8),
  ])
  let expected = [2, 3, 4, 6, 7]
  assert_eq(log.replay().unwrap().to_array(), expected)
  assert_eq(log.cardinality_history().unwrap(), [2, 4, 3, 5])
  let decoded = @moonbit-roaring.decode_operation_log(
    checkpoint,
    log.encode_words(),
  ).unwrap()
  assert_eq(decoded.replay().unwrap().to_array(), expected)
  assert_eq(decoded.cardinality_history().unwrap(), [2, 4, 3, 5])
  for count in 0..<4 {
    let (prefix, suffix) = log.split_at(count).unwrap()
    assert_eq(
      prefix.replay().unwrap().to_array(),
      suffix.checkpoint().to_array(),
    )
    assert_eq(suffix.replay().unwrap().to_array(), expected)
  }
  let compacted = log.compact().unwrap()
  assert_true(compacted.is_compacted())
  assert_eq(compacted.replay().unwrap().to_array(), expected)
  assert_eq(log.pending_patch().unwrap().apply(checkpoint).to_array(), expected)
  assert_eq(
    @moonbit-roaring.decode_operation_log(checkpoint, log.encode_words())
    .unwrap()
    .encode_words(),
    log.encode_words(),
  )
}
