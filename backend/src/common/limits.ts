/** Upper bounds for free-text input, so a client can't store unbounded strings. */
export const NAME_MAX_LENGTH = 100;
export const ADDRESS_MAX_LENGTH = 200;
export const DESCRIPTION_MAX_LENGTH = 1000;
export const URL_MAX_LENGTH = 2048;

/** Catalog photos are plain URL strings (set by the importer): http(s) only, localhost allowed for dev. User and store photos are not client-supplied. */
export const PHOTO_URL_OPTIONS = {
  protocols: ['http', 'https'],
  require_protocol: true,
  require_tld: false,
};
