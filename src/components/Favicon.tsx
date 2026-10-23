import { memo, useState } from 'react';
import { Globe2, LoaderCircle } from 'lucide-react';
export const Favicon = memo(function Favicon({ url, loading, title }: { url?: string; loading?: boolean; title?: string }) {
  const [failed, setFailed] = useState<string>();
  if (loading) return <LoaderCircle size={17} className="spin" aria-label="Loading" />;
  return <span className="favicon">{url && failed !== url ? <img src={url} alt="" referrerPolicy="no-referrer" onError={() => setFailed(url)} /> : title ? <span>{title.replace(/^www\./, '').slice(0, 1).toUpperCase()}</span> : <Globe2 size={17} />}</span>;
});
