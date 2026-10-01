import type { TransformFnParams } from 'class-transformer';

/** Phone numbers: optional leading `+`, then 8–15 digits. */
export const PHONE_NUMBER_PATTERN = /^\+?[0-9]{8,15}$/;

/** Trims strings; leaves any other value for the validators to reject. */
export function trimString({ value }: TransformFnParams): unknown {
  return typeof value === 'string' ? value.trim() : value;
}

/**
 * Strips the separators users type (spaces, dots, dashes, parentheses) so
 * `98 999 240` and `98999240` are the same number. Mirrors the Flutter form
 * validator, which accepts those separators.
 */
export function normalizePhoneNumber({ value }: TransformFnParams): unknown {
  return typeof value === 'string' ? value.replace(/[\s().-]/g, '') : value;
}
