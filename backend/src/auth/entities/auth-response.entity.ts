import { ApiProperty } from '@nestjs/swagger';
import { UserEntity } from '../../users/entities/user.entity.js';

export class AuthResponseEntity {
  @ApiProperty()
  accessToken!: string;

  @ApiProperty({ type: UserEntity })
  user!: UserEntity;
}
