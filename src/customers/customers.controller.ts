import { Body, Controller, Param, Post } from '@nestjs/common';
import { CustomersService } from './customers.service';
import { IdentifyCustomerDto } from './dto/identify-customer.dto';
import { Public } from '../common/decorators/public.decorator';

@Controller('ecommerce/public/:organizationId/customers')
@Public()
export class CustomersController {
  constructor(private readonly customersService: CustomersService) {}

  @Post('identify')
  identify(@Param('organizationId') organizationId: string, @Body() dto: IdentifyCustomerDto) {
    return this.customersService.identify(organizationId, dto.email, dto.displayName, dto.phone, dto.cartId);
  }
}
