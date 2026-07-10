import { Type } from 'class-transformer';
import { IsIn, IsInt, IsOptional, IsString, Min, ValidateNested } from 'class-validator';

class CreateVariantDto {
  @IsString() sku!: string;
  @IsString() title!: string;
  @IsInt() @Min(0) priceCents!: number;
  @IsOptional() @IsString() currency?: string;
}

export class CreateProductDto {
  @IsString() name!: string;
  @IsString() handle!: string;
  @IsOptional() @IsString() description?: string;
  @IsOptional() @IsString() categoryId?: string;
  @IsOptional() @IsIn(['DRAFT', 'PUBLISHED', 'ARCHIVED']) status?: string;

  @ValidateNested({ each: true })
  @Type(() => CreateVariantDto)
  variants!: CreateVariantDto[];
}
