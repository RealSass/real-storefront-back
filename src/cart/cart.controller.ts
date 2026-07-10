import { Body, Controller, Delete, Get, Param, Post } from '@nestjs/common';
import { CartService } from './cart.service';
import { AddItemDto } from './dto/add-item.dto';
import { Public } from '../common/decorators/public.decorator';

@Controller('ecommerce/public/:organizationId/cart')
@Public()
export class CartController {
  constructor(private readonly cartService: CartService) {}

  @Post('items')
  addItem(@Param('organizationId') organizationId: string, @Body() dto: AddItemDto) {
    return this.cartService.addItem(organizationId, dto.sessionId, dto.variantId, dto.quantity, dto.cartId);
  }

  @Delete(':cartId/items/:variantId')
  removeItem(
    @Param('organizationId') organizationId: string,
    @Param('cartId') cartId: string,
    @Param('variantId') variantId: string,
  ) {
    return this.cartService.removeItem(organizationId, cartId, variantId);
  }

  @Get(':cartId')
  get(@Param('organizationId') organizationId: string, @Param('cartId') cartId: string) {
    return this.cartService.getCart(organizationId, cartId);
  }
}
