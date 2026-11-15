from pathlib import Path
import random, pyroaring
rng=random.Random(42)
cases=[[], [0,4294967295],list(range(10000)),[i*3 for i in range(5000)], sorted(set(rng.randrange(2**32) for _ in range(128)))]
parts=['// Generated independently with pyroaring 1.2.0; regenerate using generate_croaring_fixtures.py.\n']
for i, values in enumerate(cases):
 b=pyroaring.BitMap(values)
 if i==2: b.run_optimize()
 payload=b.serialize()
 literal=''.join('\\x%02x'%x for x in payload)
 expected=','.join(str(x)+'U' for x in values)
 parts.append(f'''///|
test "CRoaring corpus {i}" {{
  let bitmap = @moonbit-roaring.decode_portable_uint32(b"{literal}").unwrap()
  let expected : Array[UInt] = [{expected}]
  assert_eq(bitmap.cardinality(), {len(values)}UL)
  for i in 0..<expected.length() {{
    assert_eq(bitmap.select(i.to_uint64()), Some(expected[i]))
  }}
}}
''')
Path('croaring_corpus_test.mbt').write_text('\n'.join(parts))
