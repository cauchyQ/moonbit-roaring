# UInt32 patch wire format v1

All integers are little endian. A patch is one frame, with no trailing bytes.

| Offset | Size | Content |
| ---: | ---: | --- |
| 0 | 4 | ASCII URP1 |
| 4 | 32 | SHA-256 of UTF-8 dataset name |
| 36 | 8 | Base generation |
| 44 | 8 | Target generation, strictly greater than base |
| 52 | 32 | SHA-256 of canonical base portable bytes |
| 84 | 32 | SHA-256 of canonical target portable bytes |
| 116 | 4 | Additions byte length |
| 120 | 4 | Removals byte length |
| 124 | variable | Additions portable bitmap, followed by removals portable bitmap |

Canonical fingerprint bytes are produced by this module's no-run portable
writer: sorted high-16-bit keys, Array for cardinality <=4096 and Bitmap
otherwise. Equivalent sets therefore produce identical digest inputs.
Changing this canonical encoding requires a new patch version.

Decoding validates dataset identity, increasing versions, bounded lengths,
portable payloads, disjoint additions/removals and exact frame consumption.
Applying checks base dataset/version and SHA-256 before updating; target
SHA-256 is verified before a new immutable snapshot is returned. Failure leaves
the original snapshot unchanged. Repeated or out-of-order delivery fails the
generation check. Restore a full snapshot when a required base is unavailable.

SHA-256 provides content integrity, not sender authentication. The outer patch
format is specific to this library; only its bitmap payloads are standard
Roaring portable data. Implementations are bounded by available memory and
the MoonBit byte-array length limit. The old non-negative Int journal remains
a separate compatibility API.
