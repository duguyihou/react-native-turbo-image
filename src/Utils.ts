export const Utils = {
  canBeAPNG: (url: string) => {
    return !!url?.toLowerCase()?.match(/.png|.apng|/);
  },
  canBeGif: (url: string) => {
    return !!url?.toLowerCase()?.match(/.gif/);
  },
  canBeSvg: (url: string) => {
    return !!url?.toLowerCase()?.match(/.svg/);
  },
};
