import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { formatReport, importCatalog } from './catalog-import.js';

/**
 * `npm run catalog:import [-- --dry-run] [-- --file <path>]`
 *
 * Exit code 0 on success (including a dry run), 1 when the file is invalid or
 * the import could not run.
 */

function readArguments(argv: string[]) {
  let dryRun = false;
  let file = 'seed/catalog.json';
  for (let i = 0; i < argv.length; i += 1) {
    const argument = argv[i];
    if (argument === '--dry-run') {
      dryRun = true;
    } else if (argument === '--file' && argv[i + 1] !== undefined) {
      file = argv[(i += 1)]!;
    } else {
      throw new Error(
        `Unknown argument "${argument}". Usage: catalog:import [--dry-run] [--file <path>]`,
      );
    }
  }
  return { dryRun, file: resolve(file) };
}

/** Host and database only — never credentials. */
function describeDatabase(): string {
  const url = new URL(process.env['DATABASE_URL'] ?? '');
  return `${url.host}${url.pathname}`;
}

async function main(): Promise<number> {
  let options: ReturnType<typeof readArguments>;
  try {
    options = readArguments(process.argv.slice(2));
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    return 1;
  }
  const { dryRun, file } = options;

  let input: unknown;
  try {
    input = JSON.parse(await readFile(file, 'utf8'));
  } catch (error) {
    console.error(
      `Cannot read ${file} as JSON: ${error instanceof Error ? error.message : String(error)}`,
    );
    return 1;
  }

  const report = await importCatalog(input, { dryRun });
  console.log(formatReport(report, { database: describeDatabase(), file }));
  return report.errors.length > 0 ? 1 : 0;
}

main()
  .then((code) => process.exit(code))
  .catch((error: unknown) => {
    console.error(error);
    process.exit(1);
  });
