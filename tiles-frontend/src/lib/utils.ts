export function isBitSet(bitmap: bigint, idx: number) {
  const one = BigInt(1) << BigInt(idx);
  return (bitmap & one) !== BigInt(0);
}

export function tileIndex(cols: number, r: number, c: number) {
  return r * cols + c;
}

export function fmtEth(v: bigint) {
  return Number(v) / 1e18;
}
