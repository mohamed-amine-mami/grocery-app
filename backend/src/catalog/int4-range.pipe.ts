import { BadRequestException, Injectable, PipeTransform } from '@nestjs/common';
import { INT4_MAX } from './dto/browse-catalog.query.js';

/**
 * Rejects an integer that does not fit a PostgreSQL `integer` column. Such a
 * value cannot match any row, but handed to the database it is a 500; here it
 * is a 400. Run it after `ParseIntPipe`. Ids inside the range are untouched
 * (an unknown one is still a 404 further on).
 */
@Injectable()
export class Int4RangePipe implements PipeTransform<number, number> {
  constructor(private readonly name: string) {}

  transform(value: number): number {
    if (value > INT4_MAX || value < -INT4_MAX - 1) {
      throw new BadRequestException(
        `${this.name} must be between ${-INT4_MAX - 1} and ${INT4_MAX}`,
      );
    }
    return value;
  }
}
