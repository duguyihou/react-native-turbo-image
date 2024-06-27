export const Utils = {
  canBeAPNG: (url: string) => {
    return !!url?.toLowerCase()?.match(/.png|.apng|/);
  },
};
