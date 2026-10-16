import { mkdirSync, writeFileSync } from "node:fs";
import { deflateSync } from "node:zlib";
function crc(b) {
  let c = 0xffffffff;
  for (const v of b) {
    c ^= v;
    for (let i = 0; i < 8; i++) c = (c >>> 1) ^ (c & 1 ? 0xedb88320 : 0);
  }
  return (c ^ 0xffffffff) >>> 0;
}
function chunk(t, b) {
  let k = Buffer.from(t),
    n = Buffer.alloc(4),
    c = Buffer.alloc(4);
  n.writeUInt32BE(b.length);
  c.writeUInt32BE(crc(Buffer.concat([k, b])));
  return Buffer.concat([n, k, b, c]);
}
function png(n) {
  let data = Buffer.alloc(n * (1 + n * 4));
  for (let y = 0; y < n; y++)
    for (let x = 0; x < n; x++) {
      let a = (x / n) * 512,
        b = (y / n) * 512;
      let ring = [175, 337].some(
        (cx) => Math.abs(Math.hypot(a - cx, b - 335) - 44) < 12,
      );
      let dist = (x1, y1, x2, y2) => {
        let t = Math.max(
          0,
          Math.min(
            1,
            ((a - x1) * (x2 - x1) + (b - y1) * (y2 - y1)) /
              ((x2 - x1) ** 2 + (y2 - y1) ** 2),
          ),
        );
        return Math.hypot(a - x1 - t * (x2 - x1), b - y1 - t * (y2 - y1));
      };
      let mark =
        ring || dist(201, 301, 338, 138) < 12 || dist(311, 301, 174, 138) < 12;
      let p = y * (1 + n * 4) + 1 + x * 4;
      data.set(mark ? [198, 166, 107, 255] : [21, 24, 21, 255], p);
    }
  let ih = Buffer.alloc(13);
  ih.writeUInt32BE(n);
  ih.writeUInt32BE(n, 4);
  ih[8] = 8;
  ih[9] = 6;
  return Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    chunk("IHDR", ih),
    chunk("IDAT", deflateSync(data)),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}
mkdirSync("public/icons", { recursive: true });
for (const [name, size] of [
  ["icon-192", 192],
  ["icon-512", 512],
  ["maskable-512", 512],
  ["apple-touch-icon", 180],
])
  writeFileSync("public/icons/" + name + ".png", png(size));
