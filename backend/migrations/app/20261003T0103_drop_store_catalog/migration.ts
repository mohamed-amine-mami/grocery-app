#!/usr/bin/env -S node
import type { Contract as End } from '../../snapshots/1b3520a9f7b86c00e4e1ebcfec95b5b38d451bf1e90a0933a56f8c091100c8ed/contract';
import endContract from '../../snapshots/1b3520a9f7b86c00e4e1ebcfec95b5b38d451bf1e90a0933a56f8c091100c8ed/contract.json' with { type: 'json' };
import type { Contract as Start } from '../../snapshots/54abcc0bd3e3d7a10ba82cfd92b9c750ca92321b0140e6e6afc5713eb0ad2b46/contract';
import startContract from '../../snapshots/54abcc0bd3e3d7a10ba82cfd92b9c750ca92321b0140e6e6afc5713eb0ad2b46/contract.json' with { type: 'json' };
import { Migration, MigrationCLI, rawSql } from '@prisma/orm-postgres/migration';

/**
 * Replaces the per-store catalog (Category/Product with a storeId) by the
 * global catalog added in the next migration. Dropping is only acceptable
 * because that data is disposable development data; the guard makes anyone
 * running this against another database opt in explicitly, e.g.
 *   --db "$DATABASE_URL?options=-c%20grocery.allow_catalog_reset%3Dyes"
 * Without it the migration aborts before touching anything.
 */
const requireOptIn = rawSql({
  id: 'guard.allowCatalogReset',
  label: 'Require explicit opt-in before dropping the per-store catalog',
  operationClass: 'data',
  target: {
    id: 'postgres',
    details: { schema: 'public', objectType: 'table', name: 'Product' },
  },
  precheck: [
    {
      description:
        'refuse to drop the per-store catalog unless grocery.allow_catalog_reset=yes is set on the connection',
      sql: `SELECT coalesce(current_setting('grocery.allow_catalog_reset', true), '') = 'yes' AS "result"`,
    },
  ],
  execute: [{ description: 'opt-in confirmed', sql: 'SELECT 1' }],
  postcheck: [],
});

export default class M extends Migration<Start, End> {
  override readonly startContractJson = startContract;
  override readonly endContractJson = endContract;

  override get operations() {
    return [
      requireOptIn,
      // Product first: it holds a foreign key to Category.
      this.dropTable({ schema: 'public', table: 'Product' }),
      this.dropTable({ schema: 'public', table: 'Category' }),
    ];
  }
}

MigrationCLI.run(import.meta.url, M);
