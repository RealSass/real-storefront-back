import { IsIn, IsObject, IsOptional, IsString } from 'class-validator';

export class LogEventDto {
  @IsString() sessionId!: string;
  @IsIn(['PRODUCT_VIEW', 'CART_ADD', 'CART_REMOVE', 'CHECKOUT_STARTED', 'ORDER_COMPLETED'])
  eventType!: string;
  @IsOptional() @IsString() customerId?: string;
  @IsOptional() @IsObject() payload?: Record<string, unknown>;
}
