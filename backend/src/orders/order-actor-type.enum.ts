/**
 * Who caused an order status change. Mirrors the `OrderActorType` enum in
 * `contract.prisma`. `CLIENT` and `OWNER` carry the user's id; `SYSTEM` carries
 * none; `CHANNEL` is an automated channel such as WhatsApp acting for a customer.
 */
export enum OrderActorType {
  CLIENT = 'CLIENT',
  OWNER = 'OWNER',
  SYSTEM = 'SYSTEM',
  CHANNEL = 'CHANNEL',
}
