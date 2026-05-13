import { useEffect, useState } from 'react';
import { Card } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Checkbox } from '@/components/ui/checkbox';
import { Textarea } from '@/components/ui/textarea';
import { Sheet, SheetContent, SheetHeader, SheetTitle, SheetTrigger } from '@/components/ui/sheet';
import { Beaker, Bug, MapPin, Send, Wifi, WifiOff } from 'lucide-react';
import { Analytics } from '@/lib/analytics/AnalyticsService';
import { useMapPerfMonitor } from '@/hooks/useMapPerfMonitor';

const CHECKPOINTS: { id: string; label: string; zone?: string }[] = [
  { id: 'kaloum_pickup', label: 'Pickup Kaloum (centre admin)', zone: 'Kaloum' },
  { id: 'madina_market', label: 'Marché Madina', zone: 'Matam' },
  { id: 'bambeto_rond', label: 'Rond-point Bambeto', zone: 'Ratoma' },
  { id: 'kipe_residence', label: 'Kipé résidence', zone: 'Ratoma' },
  { id: 'aeroport_gbessia', label: 'Aéroport Gbessia', zone: 'Matoto' },
  { id: 'cosa_carrefour', label: 'Cosa carrefour', zone: 'Ratoma' },
];

const CHECKLIST = [
  'GPS autorisé et précis (<50m)',
  'Carte chargée en moins de 3s',
  'Marqueur chauffeur glisse en douceur',
  'ETA cohérent avec le trafic réel',
  'Itinéraire évite les zones inaccessibles',
  'Re-centrage fonctionne après scroll',
  'Mode hors-ligne dégradé sans crash',
  'Bouton appel chauffeur fonctionne',
];

/**
 * Floating dev panel for in-field QA in Conakry.
 * Only mount in dev / staging or when an internal flag is on.
 */
export function FieldTestingPanel() {
  const [open, setOpen] = useState(false);
  const [checked, setChecked] = useState<Record<string, boolean>>({});
  const [note, setNote] = useState('');
  const [online, setOnline] = useState(navigator.onLine);
  const [coords, setCoords] = useState<{ lat: number; lng: number; acc: number } | null>(null);
  const { fps, degraded } = useMapPerfMonitor(open);

  useEffect(() => {
    const on = () => setOnline(true);
    const off = () => setOnline(false);
    window.addEventListener('online', on);
    window.addEventListener('offline', off);
    return () => { window.removeEventListener('online', on); window.removeEventListener('offline', off); };
  }, []);

  useEffect(() => {
    if (!open || !navigator.geolocation) return;
    const id = navigator.geolocation.watchPosition(
      (p) => setCoords({ lat: p.coords.latitude, lng: p.coords.longitude, acc: p.coords.accuracy }),
      undefined,
      { enableHighAccuracy: true, maximumAge: 5000 },
    );
    return () => navigator.geolocation.clearWatch(id);
  }, [open]);

  const startSession = () => {
    try { Analytics.track('field.test.started' as any, { metadata: { online, coords } }); } catch {}
  };

  const ping = (id: string) => {
    try { Analytics.track('field.test.checkpoint' as any, { metadata: { checkpoint: id, coords, fps } }); } catch {}
    setChecked((c) => ({ ...c, [id]: true }));
  };

  const submitNote = () => {
    if (!note.trim()) return;
    try { Analytics.track('field.test.note' as any, { metadata: { note: note.trim(), coords, fps } }); } catch {}
    setNote('');
  };

  const completeSession = () => {
    const passed = Object.values(checked).filter(Boolean).length;
    try { Analytics.track('field.test.completed' as any, { metadata: { passed, total: CHECKLIST.length, fps } }); } catch {}
    setChecked({});
    setOpen(false);
  };

  return (
    <Sheet open={open} onOpenChange={(v) => { setOpen(v); if (v) startSession(); }}>
      <SheetTrigger asChild>
        <Button
          size="icon"
          variant="secondary"
          className="fixed bottom-24 right-4 z-50 rounded-full shadow-lg border border-border"
          aria-label="Outils de test terrain"
        >
          <Beaker className="w-5 h-5" />
        </Button>
      </SheetTrigger>
      <SheetContent side="right" className="w-full sm:max-w-md overflow-y-auto">
        <SheetHeader>
          <SheetTitle className="flex items-center gap-2">
            <Bug className="w-4 h-4 text-primary" /> Test terrain — Conakry
          </SheetTitle>
        </SheetHeader>

        <div className="space-y-4 mt-4 pb-10">
          <Card className="p-3 space-y-2">
            <div className="flex items-center justify-between text-sm">
              <span className="flex items-center gap-2">
                {online ? <Wifi className="w-4 h-4 text-emerald-600" /> : <WifiOff className="w-4 h-4 text-rose-600" />}
                Réseau
              </span>
              <Badge variant={online ? 'secondary' : 'destructive'}>{online ? 'En ligne' : 'Hors ligne'}</Badge>
            </div>
            <div className="flex items-center justify-between text-sm">
              <span>FPS carte</span>
              <Badge variant={degraded ? 'destructive' : 'secondary'} className="font-mono">{fps}</Badge>
            </div>
            <div className="flex items-center justify-between text-sm">
              <span className="flex items-center gap-2"><MapPin className="w-4 h-4" /> Position</span>
              <span className="text-xs text-muted-foreground">
                {coords ? `±${Math.round(coords.acc)} m` : '—'}
              </span>
            </div>
          </Card>

          <div>
            <h4 className="text-xs uppercase tracking-wide text-muted-foreground mb-2">Points de contrôle</h4>
            <div className="grid grid-cols-2 gap-2">
              {CHECKPOINTS.map((c) => (
                <Button
                  key={c.id}
                  variant={checked[c.id] ? 'default' : 'outline'}
                  size="sm"
                  className="justify-start h-auto py-2 text-left"
                  onClick={() => ping(c.id)}
                >
                  <div className="text-xs leading-tight">
                    <p className="font-medium">{c.label}</p>
                    {c.zone && <p className="text-[10px] opacity-70">{c.zone}</p>}
                  </div>
                </Button>
              ))}
            </div>
          </div>

          <div>
            <h4 className="text-xs uppercase tracking-wide text-muted-foreground mb-2">Checklist QA</h4>
            <div className="space-y-2">
              {CHECKLIST.map((item, i) => {
                const id = `qa-${i}`;
                return (
                  <label key={id} className="flex items-start gap-2 text-sm cursor-pointer">
                    <Checkbox
                      id={id}
                      checked={!!checked[id]}
                      onCheckedChange={(v) => setChecked((c) => ({ ...c, [id]: !!v }))}
                    />
                    <span>{item}</span>
                  </label>
                );
              })}
            </div>
          </div>

          <div>
            <h4 className="text-xs uppercase tracking-wide text-muted-foreground mb-2">Note rapide</h4>
            <Textarea
              value={note}
              onChange={(e) => setNote(e.target.value)}
              placeholder="Ex : ETA Madina→Kaloum sous-estime de 4 min en heure de pointe…"
              rows={3}
            />
            <Button size="sm" onClick={submitNote} className="mt-2 gap-1.5" disabled={!note.trim()}>
              <Send className="w-3.5 h-3.5" /> Envoyer la note
            </Button>
          </div>

          <Button onClick={completeSession} variant="default" className="w-full">
            Terminer la session
          </Button>
        </div>
      </SheetContent>
    </Sheet>
  );
}