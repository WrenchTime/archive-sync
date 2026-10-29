// Builds the trouble-code catalog the WrenchTime app downloads: one flat
// { "CODE": "short title" } file per language OBDex writes itself, from the
// YAML under data/generic of the OBDex fork. Reads data only; nothing of
// the OBDex repository is executed.
//
// Usage: bun dtc-catalog.ts <obdex>/data/generic <output dir>

import { Glob } from "bun";

const [dataDir, outDir] = Bun.argv.slice(2);

// Same files, same order as OBDex's own build: every .yaml under
// data/generic, each a top-level array of entries.
const files = [...new Glob("**/*.yaml").scanSync(dataDir)].sort();
const entries: any[] = [];
for (const file of files) {
    const parsed = Bun.YAML.parse(await Bun.file(`${dataDir}/${file}`).text());
    if (Array.isArray(parsed)) entries.push(...parsed);
}

for (const language of ["en", "de"]) {
    const table: Record<string, string> = {};
    let conflicts = 0;
    for (const entry of entries) {
        const code = String(entry?.code ?? "").trim().toUpperCase();
        const title = entry?.title?.[language];
        if (!code || typeof title !== "string" || !title.trim()) continue;
        if (code in table && table[code] !== title.trim()) {
            conflicts++;
            continue;
        }
        table[code] ??= title.trim();
    }
    if (conflicts) console.log(`  warning: ${conflicts} conflicting duplicate code(s) for '${language}', kept first`);
    const sorted = Object.fromEntries(Object.keys(table).sort().map((key) => [key, table[key]]));
    const outPath = `${outDir}/dtc-generic-${language}.json`;
    await Bun.write(outPath, JSON.stringify(sorted, null, 2) + "\n");
    console.log(`Wrote ${outPath}: ${Object.keys(sorted).length} codes`);
}
