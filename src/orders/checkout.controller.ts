import { Body, Controller, Param, Post } from '@nestjs/common';
import { OrdersService } from './orders.service';
import { CheckoutDto } from './dto/checkout.dto';
import { Public } from '../common/decorators/public.decorator';

// Público — el cliente final finaliza la compra. Sin Firebase.
@Controller('ecommerce/public/:organizationId/checkout')
@Public()
export class CheckoutController {
  constructor(private readonly ordersService: OrdersService) {}

  @Post()
  checkout(@Param('organizationId') organizationId: string, @Body() dto: CheckoutDto) {
    return this.ordersService.checkout(organizationId, dto);
  }
}
