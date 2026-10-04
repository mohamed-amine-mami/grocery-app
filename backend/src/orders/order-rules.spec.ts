import { ConflictException } from '@nestjs/common';
import { readFileSync } from 'node:fs';
import {
  MAX_ORDER_TOTAL_MILLIMES,
  MAX_PICKUP_LEAD_HOURS,
  MIN_PICKUP_LEAD_MINUTES,
  ORDER_CODE_ALPHABET,
  ORDER_CODE_LENGTH,
  ORDER_STATE_CHANGED,
  ORDER_TRANSITIONS,
  canTransition,
  decideTransition,
  generateOrderCode,
  isOrderCode,
  isTerminalStatus,
  orderStateChanged,
  orderTotalMillimes,
  pickupTimeError,
  resolveTransition,
} from './order-rules.js';
import { OrderStatus } from './order-status.enum.js';

const { PENDING, CONFIRMED, READY_FOR_PICKUP, COMPLETED, CANCELLED, NO_SHOW } =
  OrderStatus;
const ALL = Object.values(OrderStatus);

const VALID_TRANSITIONS: [OrderStatus, OrderStatus][] = [
  [PENDING, CONFIRMED],
  [PENDING, CANCELLED],
  [CONFIRMED, READY_FOR_PICKUP],
  [CONFIRMED, CANCELLED],
  [READY_FOR_PICKUP, COMPLETED],
  [READY_FOR_PICKUP, NO_SHOW],
];

describe('OrderStatus', () => {
  it('has exactly the statuses of the database enum', () => {
    const contract = JSON.parse(
      readFileSync(new URL('../prisma/contract.json', import.meta.url), 'utf8'),
    );
    const dbValues =
      contract.storage.namespaces.public.entries.valueSet.OrderStatus.values;
    const byName = (a: string, b: string) => a.localeCompare(b);
    expect([...ALL].sort(byName)).toEqual([...dbValues].sort(byName));
  });
});

describe('lifecycle', () => {
  it.each(VALID_TRANSITIONS)('allows %s → %s', (from, to) => {
    expect(canTransition(from, to)).toBe(true);
    expect(decideTransition(from, to)).toBe('apply');
    expect(resolveTransition(from, to)).toBe('apply');
  });

  const invalid = ALL.flatMap((from) =>
    ALL.filter(
      (to) =>
        to !== from &&
        !VALID_TRANSITIONS.some(([f, t]) => f === from && t === to),
    ).map((to) => [from, to] as [OrderStatus, OrderStatus]),
  );

  it('has exactly 6 valid and 24 invalid changes of status (6 × 5 = 30)', () => {
    expect(VALID_TRANSITIONS).toHaveLength(6);
    expect(invalid).toHaveLength(24);
  });

  it.each(invalid)('rejects %s → %s', (from, to) => {
    expect(canTransition(from, to)).toBe(false);
    expect(decideTransition(from, to)).toBe('invalid');
    expect(() => resolveTransition(from, to)).toThrow(ConflictException);
  });

  it('lists exactly the allowed targets for each status', () => {
    expect(ORDER_TRANSITIONS).toEqual({
      PENDING: ['CONFIRMED', 'CANCELLED'],
      CONFIRMED: ['READY_FOR_PICKUP', 'CANCELLED'],
      READY_FOR_PICKUP: ['COMPLETED', 'NO_SHOW'],
      COMPLETED: [],
      CANCELLED: [],
      NO_SHOW: [],
    });
  });

  it.each([COMPLETED, CANCELLED, NO_SHOW])(
    '%s is terminal: every other status is rejected',
    (terminal) => {
      expect(isTerminalStatus(terminal)).toBe(true);
      for (const to of ALL.filter((status) => status !== terminal)) {
        expect(canTransition(terminal, to)).toBe(false);
        expect(decideTransition(terminal, to)).toBe('invalid');
      }
    },
  );

  it.each([PENDING, CONFIRMED, READY_FOR_PICKUP])(
    '%s is not terminal',
    (status) => {
      expect(isTerminalStatus(status)).toBe(false);
    },
  );

  it('nothing moves back to PENDING, and nothing skips CONFIRMED to READY', () => {
    for (const from of ALL) expect(canTransition(from, PENDING)).toBe(false);
    expect(canTransition(PENDING, READY_FOR_PICKUP)).toBe(false);
    expect(canTransition(PENDING, COMPLETED)).toBe(false);
    expect(canTransition(CONFIRMED, COMPLETED)).toBe(false);
  });

  it('cannot cancel a ready order (it ends COMPLETED or NO_SHOW)', () => {
    expect(canTransition(READY_FOR_PICKUP, CANCELLED)).toBe(false);
  });
});

describe('same-status requests', () => {
  it.each(ALL)('%s → %s is unchanged: no change, no event', (status) => {
    expect(decideTransition(status, status)).toBe('unchanged');
    expect(resolveTransition(status, status)).toBe('unchanged');
    // Staying put is never an allowed *change* of status.
    expect(canTransition(status, status)).toBe(false);
  });

  it('is idempotent even for terminal states', () => {
    expect(resolveTransition(COMPLETED, COMPLETED)).toBe('unchanged');
    expect(resolveTransition(CANCELLED, CANCELLED)).toBe('unchanged');
    expect(resolveTransition(NO_SHOW, NO_SHOW)).toBe('unchanged');
  });
});

describe('the invalid-transition error', () => {
  it('is the stable 409 ORDER_STATE_CHANGED, carrying the current status', () => {
    const error = orderStateChanged(COMPLETED, CANCELLED);
    expect(error).toBeInstanceOf(ConflictException);
    expect(error.getStatus()).toBe(409);
    expect(error.getResponse()).toEqual({
      statusCode: 409,
      error: 'Conflict',
      code: 'ORDER_STATE_CHANGED',
      message: 'Order is COMPLETED; it cannot move to CANCELLED',
      currentStatus: 'COMPLETED',
      requestedStatus: 'CANCELLED',
    });
    expect(ORDER_STATE_CHANGED).toBe('ORDER_STATE_CHANGED');
  });

  it('is what resolveTransition throws', () => {
    try {
      resolveTransition(PENDING, COMPLETED);
      expect.unreachable();
    } catch (error) {
      expect((error as ConflictException).getResponse()).toMatchObject({
        code: 'ORDER_STATE_CHANGED',
        currentStatus: 'PENDING',
        requestedStatus: 'COMPLETED',
      });
    }
  });
});

describe('pickupTimeError', () => {
  const now = new Date('2026-10-04T10:00:00.000Z');
  const at = (ms: number) => new Date(now.getTime() + ms);
  const MIN = 60_000;
  const HOUR = 60 * MIN;

  it('uses 30 minutes and 48 hours', () => {
    expect(MIN_PICKUP_LEAD_MINUTES).toBe(30);
    expect(MAX_PICKUP_LEAD_HOURS).toBe(48);
  });

  it('accepts a time inside the bounds', () => {
    expect(pickupTimeError(at(8 * HOUR), now)).toBeNull(); // "this evening"
    expect(pickupTimeError(at(24 * HOUR), now)).toBeNull();
  });

  it('accepts exactly the lower bound (30 minutes)', () => {
    expect(pickupTimeError(at(30 * MIN), now)).toBeNull();
  });

  it('rejects one millisecond below the lower bound', () => {
    expect(pickupTimeError(at(30 * MIN - 1), now)).toBe(
      'requestedPickupAt must be at least 30 minutes from now',
    );
  });

  it('rejects now and the past', () => {
    expect(pickupTimeError(at(0), now)).toMatch(/at least 30 minutes/);
    expect(pickupTimeError(at(-HOUR), now)).toMatch(/at least 30 minutes/);
  });

  it('accepts exactly the upper bound (48 hours)', () => {
    expect(pickupTimeError(at(48 * HOUR), now)).toBeNull();
  });

  it('rejects one millisecond above the upper bound', () => {
    expect(pickupTimeError(at(48 * HOUR + 1), now)).toBe(
      'requestedPickupAt must be at most 48 hours from now',
    );
  });

  it('rejects an invalid date', () => {
    expect(pickupTimeError(new Date('not a date'), now)).toBe(
      'requestedPickupAt must be a valid date',
    );
  });

  it('measures from the clock it is given, not the machine clock', () => {
    const later = new Date('2030-01-01T09:00:00.000Z');
    expect(
      pickupTimeError(new Date('2030-01-01T10:00:00.000Z'), later),
    ).toBeNull();
    expect(
      pickupTimeError(new Date('2026-10-04T12:00:00.000Z'), later),
    ).toMatch(/at least/);
  });
});

describe('orderTotalMillimes', () => {
  const line = (lineTotalMillimes: number, removedAt: Date | null = null) => ({
    lineTotalMillimes,
    removedAt,
  });

  it('sums the lines', () => {
    expect(orderTotalMillimes([line(900), line(350), line(1200)])).toBe(2450);
  });

  it('counts removed lines for zero', () => {
    expect(
      orderTotalMillimes([line(900), line(5000, new Date()), line(350)]),
    ).toBe(1250);
    expect(orderTotalMillimes([line(5000, new Date('2026-10-04'))])).toBe(0);
  });

  it('accepts a removedAt given as an ISO string', () => {
    expect(
      orderTotalMillimes([
        line(900),
        { lineTotalMillimes: 100, removedAt: '2026-10-04T10:00:00Z' },
      ]),
    ).toBe(900);
  });

  it('is zero for no lines', () => {
    expect(orderTotalMillimes([])).toBe(0);
  });

  it('is exact: 0.1 + 0.2 style drift cannot happen with integer millimes', () => {
    // Many small lines whose float sum would drift.
    const lines = Array.from({ length: 1000 }, () => line(1));
    expect(orderTotalMillimes(lines)).toBe(1000);
    expect(orderTotalMillimes([line(100), line(200)])).toBe(300);
  });

  it('adds up to the exact value near the 32-bit limit', () => {
    expect(
      orderTotalMillimes([line(MAX_ORDER_TOTAL_MILLIMES - 5), line(5)]),
    ).toBe(MAX_ORDER_TOTAL_MILLIMES);
  });

  it('refuses a total the 32-bit column cannot hold', () => {
    expect(() =>
      orderTotalMillimes([line(MAX_ORDER_TOTAL_MILLIMES), line(1)]),
    ).toThrow(RangeError);
  });

  it('does not count removed lines toward the limit', () => {
    expect(
      orderTotalMillimes([
        line(MAX_ORDER_TOTAL_MILLIMES),
        line(MAX_ORDER_TOTAL_MILLIMES, new Date()),
      ]),
    ).toBe(MAX_ORDER_TOTAL_MILLIMES);
  });

  it.each([[-1], [1.5], [Number.NaN], [Infinity]])(
    'rejects a line total of %s',
    (bad) => {
      expect(() => orderTotalMillimes([line(bad)])).toThrow(RangeError);
    },
  );
});

describe('order codes', () => {
  it('has an alphabet without look-alike characters', () => {
    expect(ORDER_CODE_ALPHABET).toHaveLength(31);
    expect(new Set(ORDER_CODE_ALPHABET).size).toBe(31);
    for (const banned of ['0', 'O', '1', 'I', 'L']) {
      expect(ORDER_CODE_ALPHABET).not.toContain(banned);
    }
    expect(ORDER_CODE_ALPHABET).toMatch(/^[A-Z0-9]+$/);
  });

  it('generates a 6-character code from the alphabet', () => {
    for (let i = 0; i < 200; i += 1) {
      const code = generateOrderCode();
      expect(code).toHaveLength(ORDER_CODE_LENGTH);
      expect(code).toMatch(/^[A-Z0-9]{6}$/);
      expect(isOrderCode(code)).toBe(true);
    }
  });

  it('fits the database constraint (4–12 uppercase letters and digits)', () => {
    expect(generateOrderCode()).toMatch(/^[A-Z0-9]{4,12}$/);
  });

  it('is random: many codes are not all the same, and rarely collide', () => {
    const codes = new Set(
      Array.from({ length: 2000 }, () => generateOrderCode()),
    );
    // 2000 draws from ~887 million: a collision is astronomically unlikely.
    expect(codes.size).toBe(2000);
  });

  it('uses every position of the alphabet (injected generator)', () => {
    const sequence = [0, 1, 2, 30, 15, 7];
    let index = 0;
    const code = generateOrderCode((max) => {
      expect(max).toBe(31);
      return sequence[index++]!;
    });
    expect(code).toBe(
      [0, 1, 2, 30, 15, 7].map((i) => ORDER_CODE_ALPHABET[i]).join(''),
    );
  });

  it('never indexes outside the alphabet', () => {
    expect(generateOrderCode(() => 30)).toBe('ZZZZZZ');
    expect(generateOrderCode(() => 0)).toBe('222222');
  });

  it.each([
    ['AB12CD', false], // contains 1 (look-alike)
    ['ABCDEF', true],
    ['abcdef', false],
    ['ABCDE', false],
    ['ABCDEFG', false],
    ['ABC0EF', false],
    ['', false],
  ])('isOrderCode(%j) is %s', (value, expected) => {
    expect(isOrderCode(value)).toBe(expected);
  });
});
