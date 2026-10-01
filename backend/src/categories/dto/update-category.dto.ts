import { CreateCategoryDto } from './create-category.dto.js';

/** A category has a single editable field, so a rename sends the same payload as a create. */
export class UpdateCategoryDto extends CreateCategoryDto {}
