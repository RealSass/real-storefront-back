import { IsInt, IsOptional, IsString, Min } from 'class-validator';

export class AddItemDto {
  @IsString() sessionId!: string;
  @IsOptional() @IsString() cartId?: string;
  @IsString() variantId!: string;
  @IsInt() @Min(1) quantity!: number;
}
