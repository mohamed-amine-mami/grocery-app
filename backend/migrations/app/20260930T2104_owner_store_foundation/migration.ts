#!/usr/bin/env -S node
import type { Contract as End } from '../../snapshots/5e37fd12947e385c5cbfae22150046277d7430f14bcf943b7318ccb0de024f48/contract';
import endContract from '../../snapshots/5e37fd12947e385c5cbfae22150046277d7430f14bcf943b7318ccb0de024f48/contract.json' with { type: 'json' };
import type { Contract as Start } from '../../snapshots/cb3a0deb49240ac646a6b9e254759abdf8332684f5c8812da99293d337d09079/contract';
import startContract from '../../snapshots/cb3a0deb49240ac646a6b9e254759abdf8332684f5c8812da99293d337d09079/contract.json' with { type: 'json' };
import { Migration, MigrationCLI, col, lit, rawSql } from '@prisma/orm-postgres/migration';

/**
 * Data backfill as a raw op: the query builder can't express a per-row unique
 * value, and `address` / `phoneNumber` must be filled before NOT NULL applies.
 */
function backfill(id: string, label: string, table: string, column: string, sql: string) {
  const nullCheck = `SELECT NOT EXISTS (SELECT 1 FROM "public"."${table}" WHERE "${column}" IS NULL) AS "result"`;
  return rawSql({
    id,
    label,
    operationClass: 'data',
    target: {
      id: 'postgres',
      details: { schema: 'public', objectType: 'table', name: table },
    },
    precheck: [],
    execute: [{ description: label, sql }],
    postcheck: [{ description: `verify no NULL ${table}.${column}`, sql: nullCheck }],
  });
}

export default class M extends Migration<Start, End> {
  override readonly startContractJson = startContract;
  override readonly endContractJson = endContract;

  override get operations() {
    return [
      this.addColumn({
        schema: 'public',
        table: 'Store',
        column: col('isOpen', 'bool', {
          notNull: true,
          default: lit(false),
          codecRef: { codecId: 'pg/bool@1' },
        }),
      }),
      this.addColumn({
        schema: 'public',
        table: 'Store',
        column: col('address', 'text', { codecRef: { codecId: 'pg/text@1' } }),
      }),
      backfill(
        'data.Store.address.backfill',
        'Backfill missing Store.address with a placeholder the owner can edit',
        'Store',
        'address',
        `UPDATE "public"."Store" SET "address" = 'Adresse à renseigner' WHERE "address" IS NULL`,
      ),
      this.setNotNull({ schema: 'public', table: 'Store', column: 'address' }),
      backfill(
        'data.User.phoneNumber.backfill',
        'Give phone-less legacy users a unique placeholder (they could never log in by phone)',
        'User',
        'phoneNumber',
        `UPDATE "public"."User" SET "phoneNumber" = 'inconnu-' || "id" WHERE "phoneNumber" IS NULL`,
      ),
      this.setNotNull({ schema: 'public', table: 'User', column: 'phoneNumber' }),
      this.addCheckConstraint({
        schema: 'public',
        table: 'Store',
        constraint: 'store_coordinates_together_5072a0f2',
        expression: '(latitude IS NULL) = (longitude IS NULL)',
      }),
    ];
  }
}

MigrationCLI.run(import.meta.url, M);
