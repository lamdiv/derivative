import brand from '../../assets/brand.json';

/** One vector mark for the app icon, New Tab, and About. */
export function BrandMark({ className = '' }: { className?: string }) {
  return <svg className={`brand-mark ${className}`} viewBox={brand.viewBox} fill="none" aria-hidden="true" focusable="false">
    <path d={brand.bowl} stroke="currentColor" strokeWidth="8" strokeLinecap="round" strokeLinejoin="round" />
    <path d={brand.prime} stroke="currentColor" strokeWidth="5" strokeLinecap="round" />
  </svg>;
}
