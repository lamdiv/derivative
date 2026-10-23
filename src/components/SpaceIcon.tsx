import { Cloud, Diamond, Flower, Sun } from 'lucide-react';

export function SpaceIcon({ icon }: { icon: string }) {
  const Icon = ({ '✳': Flower, '✿': Flower, '◈': Diamond, '☀': Sun, '☁': Cloud } as Record<string, typeof Sun>)[icon];
  return <span className="space-icon" aria-hidden="true">{Icon ? <Icon size={18} strokeWidth={1.8} /> : <span>{icon}</span>}</span>;
}
