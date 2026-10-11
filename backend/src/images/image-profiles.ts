/**
 * How an uploaded image is processed. A profile is the one place a kind of
 * image (avatar, store photo, a future one) states its size and crop, so
 * adding a kind never touches the storage code.
 */
export interface ImageProfile {
  readonly name: string;
  /** Applied once at upload; the original is not kept. Cloudinary transformation syntax. */
  readonly uploadTransformation: string;
}

/** Square 512 px, cropped around the subject. */
export const USER_AVATAR_PROFILE: ImageProfile = {
  name: 'user-avatar',
  uploadTransformation: 'c_fill,g_auto,w_512,h_512',
};

/** At most 1200 px wide, never cropped or enlarged. */
export const STORE_PHOTO_PROFILE: ImageProfile = {
  name: 'store-photo',
  uploadTransformation: 'c_limit,w_1200',
};

/** Applied to every delivered URL: best format and quality for the device. */
export const DELIVERY_TRANSFORMATION = 'f_auto,q_auto';
