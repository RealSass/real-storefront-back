import { Global, Module } from '@nestjs/common';
import { RedisModule } from '../redis/redis.module';
import { OrganizationsClientService } from './organizations-client.service';

@Global()
@Module({
  imports: [RedisModule],
  providers: [OrganizationsClientService],
  exports: [OrganizationsClientService],
})
export class OrganizationsClientModule {}
