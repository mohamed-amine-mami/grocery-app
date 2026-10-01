/** Upper bounds for free-text input, so a client can't store unbounded strings. */
export const NAME_MAX_LENGTH = 100;
export const ADDRESS_MAX_LENGTH = 200;
export const DESCRIPTION_MAX_LENGTH = 1000;
export const URL_MAX_LENGTH = 2048;

/** Photos are plain URL strings for now (no upload): http(s) only, localhost allowed for dev. */
export const PHOTO_URL_OPTIONS = {
  protocols: ['http', 'https'],
  require_protocol: true,
  require_tld: false,
};
