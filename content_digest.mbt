// SHA-256 content fingerprint, following FIPS 180-4.

///|
fn rotate_right(value : UInt32, bits : Int32) -> UInt32 {
  (value >> bits) | (value << (32 - bits))
}

///|
fn content_digest(input : Bytes) -> Bytes {
  let k : Array[UInt32] = [
    0x428a2f98U, 0x71374491U, 0xb5c0fbcfU, 0xe9b5dba5U, 0x3956c25bU, 0x59f111f1U,
    0x923f82a4U, 0xab1c5ed5U, 0xd807aa98U, 0x12835b01U, 0x243185beU, 0x550c7dc3U,
    0x72be5d74U, 0x80deb1feU, 0x9bdc06a7U, 0xc19bf174U, 0xe49b69c1U, 0xefbe4786U,
    0xfc19dc6U, 0x240ca1ccU, 0x2de92c6fU, 0x4a7484aaU, 0x5cb0a9dcU, 0x76f988daU,
    0x983e5152U, 0xa831c66dU, 0xb00327c8U, 0xbf597fc7U, 0xc6e00bf3U, 0xd5a79147U,
    0x6ca6351U, 0x14292967U, 0x27b70a85U, 0x2e1b2138U, 0x4d2c6dfcU, 0x53380d13U,
    0x650a7354U, 0x766a0abbU, 0x81c2c92eU, 0x92722c85U, 0xa2bfe8a1U, 0xa81a664bU,
    0xc24b8b70U, 0xc76c51a3U, 0xd192e819U, 0xd6990624U, 0xf40e3585U, 0x106aa070U,
    0x19a4c116U, 0x1e376c08U, 0x2748774cU, 0x34b0bcb5U, 0x391c0cb3U, 0x4ed8aa4aU,
    0x5b9cca4fU, 0x682e6ff3U, 0x748f82eeU, 0x78a5636fU, 0x84c87814U, 0x8cc70208U,
    0x90befffaU, 0xa4506cebU, 0xbef9a3f7U, 0xc67178f2U,
  ]
  let state : Array[UInt32] = [
    0x6a09e667U, 0xbb67ae85U, 0x3c6ef372U, 0xa54ff53aU, 0x510e527fU, 0x9b05688cU,
    0x1f83d9abU, 0x5be0cd19U,
  ]
  let buf = @buffer.Buffer::Buffer()
  buf.write_bytes(input[:])
  buf.write_byte(128)
  while buf.length() % 64 != 56 {
    buf.write_byte(0)
  }
  buf.write_uint64_be(input.length().to_uint64() * 8UL)
  let padded = buf.to_bytes()
  let mut offset = 0
  while offset < padded.length() {
    let w : Array[UInt32] = Array::make(64, 0U)
    for i in 0..<16 {
      w[i] = padded.unsafe_read_uint32_be(offset + i * 4)
    }
    for i in 16..<64 {
      let x = w[i - 15]
      let y = w[i - 2]
      w[i] = w[i - 16] +
        (rotate_right(x, 7) ^ rotate_right(x, 18) ^ (x >> 3)) +
        w[i - 7] +
        (rotate_right(y, 17) ^ rotate_right(y, 19) ^ (y >> 10))
    }
    let mut a = state[0]
    let mut b = state[1]
    let mut c = state[2]
    let mut d = state[3]
    let mut e = state[4]
    let mut f = state[5]
    let mut g = state[6]
    let mut h = state[7]
    for i in 0..<64 {
      let t1 = h +
        (rotate_right(e, 6) ^ rotate_right(e, 11) ^ rotate_right(e, 25)) +
        ((e & f) ^ ((e ^ 0xffffffffU) & g)) +
        k[i] +
        w[i]
      let t2 = (rotate_right(a, 2) ^ rotate_right(a, 13) ^ rotate_right(a, 22)) +
        ((a & b) ^ (a & c) ^ (b & c))
      h = g
      g = f
      f = e
      e = d + t1
      d = c
      c = b
      b = a
      a = t1 + t2
    }
    state[0] += a
    state[1] += b
    state[2] += c
    state[3] += d
    state[4] += e
    state[5] += f
    state[6] += g
    state[7] += h
    offset += 64
  }
  let output = @buffer.Buffer::Buffer()
  for word in state {
    output.write_uint_be(word)
  }
  output.to_bytes()
}
