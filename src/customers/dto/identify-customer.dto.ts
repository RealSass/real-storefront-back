import { IsEmail, IsOptional, IsString } from 'class-validator';

export class IdentifyCustomerDto {
  @IsEmail() email!: string;
  @IsOptional() @IsString() displayName?: string;
  @IsOptional() @IsString() phone?: string;
  @IsOptional() @IsString() cartId?: string;
}
