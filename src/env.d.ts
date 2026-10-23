import type { BrowserBridge } from '../shared/types';
declare global { interface Window { browser?: BrowserBridge } }
export {};
