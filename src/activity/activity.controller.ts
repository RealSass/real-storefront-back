import { Body, Controller, Param, Post } from '@nestjs/common';
import { ActivityService } from './activity.service';
import { LogEventDto } from './dto/log-event.dto';
import { Public } from '../common/decorators/public.decorator';

@Controller('ecommerce/public/:organizationId/activity')
@Public()
export class ActivityController {
  constructor(private readonly activityService: ActivityService) {}

  @Post()
  log(@Param('organizationId') organizationId: string, @Body() dto: LogEventDto) {
    return this.activityService.log(organizationId, dto.sessionId, dto.eventType, dto.customerId, dto.payload);
  }
}
