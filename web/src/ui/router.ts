import { useEffect, useState } from 'react';

/** Tiny hash router (static hosting friendly, no dependency). */
export function useRoute(): string[] {
  const parse = () => (location.hash.replace(/^#\/?/, '') || 'dashboard').split('/').map(decodeURIComponent);
  const [route, setRoute] = useState(parse);
  useEffect(() => {
    const on = () => { setRoute(parse()); window.scrollTo(0, 0); };
    addEventListener('hashchange', on);
    return () => removeEventListener('hashchange', on);
  }, []);
  return route;
}
export const href = (...parts: string[]) => '#/' + parts.map(encodeURIComponent).join('/');
