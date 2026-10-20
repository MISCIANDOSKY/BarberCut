import test from "node:test";
import assert from "node:assert/strict";
import { readdir, readFile } from "node:fs/promises";
async function sources(directory = "src") {
  const entries = await readdir(directory, { withFileTypes: true });
  return (
    await Promise.all(
      entries.map(async (entry) =>
        entry.isDirectory()
          ? sources(directory + "/" + entry.name)
          : entry.name.endsWith(".tsx")
            ? [
                {
                  path: directory + "/" + entry.name,
                  text: await readFile(directory + "/" + entry.name, "utf8"),
                },
              ]
            : [],
      ),
    )
  ).flat();
}
test("PWA screens use integrated confirmations and selection controls", async () => {
  for (const file of await sources()) {
    assert.doesNotMatch(
      file.text,
      /(?:^|[^\w.])(?:window\.)?(?:alert|confirm|prompt)\s*\(/m,
      file.path + ": native message dialog",
    );
    assert.doesNotMatch(file.text, /<select\b/, file.path + ": native select");
    for (const input of file.text.matchAll(/<input\b([\s\S]*?)\/>/g))
      assert.doesNotMatch(
        input[1],
        /type=["'](?:date|time|datetime-local|color)["']/,
        file.path + ": native picker",
      );
  }
});
test("native validation bubbles are prevented and keyboard cancellation remains integrated", async () => {
  const text = await readFile("src/components/AppDialogs.tsx", "utf8");
  assert.match(text, /event\.preventDefault\(\)/);
  assert.match(text, /addEventListener\("invalid", invalid, true\)/);
  assert.match(text, /close=\{\(\) => answer\(false\)\}/);
});
