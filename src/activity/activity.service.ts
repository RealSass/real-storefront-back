import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class ActivityService {
  constructor(private readonly prisma: PrismaService) {}

  // Append-only — no hay update ni delete. Errores acá no deben tumbar el
  // flujo de compra: quien llama debe tratar esto como best-effort.
  async log(
    organizationId: string,
    sessionId: string,
    eventType: string,
    customerId?: string,
    payload: Record<string, unknown> = {},
  ) {
    return this.prisma.customerActivityEvent.create({
      data: { organizationId, sessionId, eventType: eventType as any, customerId, payload },
    });
  }
}
