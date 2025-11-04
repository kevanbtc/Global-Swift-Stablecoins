import { readFileSync } from "fs";
import { createReadStream } from "fs";
import { parse } from "csv-parse";
import Ajv from "ajv";
import addFormats from "ajv-formats";
import { parse as parseDate, isValid, addDays } from "date-fns";
import * as yaml from "js-yaml";

type Lot = { maturity: bigint; weight: bigint };

async function readCsv(path: string): Promise<any[]> {
  return new Promise((resolve, reject) => {
    const rows: any[] = [];
    createReadStream(path)
      .pipe(parse({ columns: true, skip_empty_lines: true }))
      .on("data", r => rows.push(r))
      .on("end", () => resolve(rows))
      .on("error", reject);
  });
}

function toLots(rows: any[], maturityCol: string, weightCol: string, dateFmt: string, settlePlus: number): Lot[] {
  const lots: Lot[] = [];
  for (const row of rows) {
    const rawDate = String(row[maturityCol] ?? "").trim();
    const rawWeight = String(row[weightCol] ?? "").replace(/[,\s]/g, "");
    if (!rawDate || !rawWeight) continue;

    let d = parseDate(rawDate, dateFmt, new Date());
    if (!isValid(d)) d = new Date(rawDate);
    if (!isValid(d)) continue;
    if (settlePlus > 0) d = addDays(d, settlePlus);

    const w = BigInt(rawWeight);
    if (w <= 0n) continue;

    const maturity = BigInt(Math.floor(d.getTime() / 1000));
    lots.push({ maturity, weight: w });
  }
  return lots;
}

async function main() {
  const mapping = yaml.load(readFileSync("schemas/mapping.wam.yaml","utf8")) as any;
  const ajv = new Ajv({ allErrors: true, allowUnionTypes: true });
  addFormats(ajv);

  const srcName = process.argv[2];
  const csvPath = process.argv[3];
  if (!srcName || !csvPath) {
    console.error("Usage: pnpm tsx scripts/normalize-to-wam.ts <sourceName> <csvPath>");
    process.exit(1);
  }
  const src = (mapping.sources as any[]).find(s => s.name === srcName);
  if (!src) throw new Error(`Unknown source: ${srcName}`);

  const schema = JSON.parse(readFileSync(src.schema, "utf8"));
  const validate = ajv.compile(schema);

  const rows = await readCsv(csvPath);
  const bad: any[] = [];
  const good: any[] = [];
  for (const r of rows) {
    if (validate(r)) good.push(r);
    else bad.push({ r, e: validate.errors });
  }
  if (bad.length) {
    console.warn(`⚠ ${bad.length} rows failed schema, continuing with ${good.length}.`);
  }

  let lots = toLots(good, src.maturityCol, src.weightCol, src.dateFmt, src.settlePlus ?? 0);

  if (mapping.output?.sortByDate) lots = lots.sort((a,b)=> (a.maturity < b.maturity ? -1 : 1));
  const chunkSize = mapping.output?.chunkSize ?? 64;
  const batches: Array<Lot[]> = [];
  for (let i=0;i<lots.length;i+=chunkSize) batches.push(lots.slice(i, i+chunkSize));

  console.log(JSON.stringify({ batches }, null, 2));
}

main().catch(e=>{ console.error(e); process.exit(1); });
