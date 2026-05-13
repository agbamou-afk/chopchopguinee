import { supabase } from '@/integrations/supabase/client';
import type { RouteProvider, NormalizedRoute, RouteRequest, EtaMatrixCell, RouteMode } from './types';
import type { LatLng } from '../geo';

export const googleProvider: RouteProvider = {
  name: 'google',
  async route(req: RouteRequest): Promise<NormalizedRoute> {
    const { data, error } = await supabase.functions.invoke('maps-route', { body: req });
    if (error) throw error;
    if ((data as any)?.error) throw new Error((data as any).error);
    return data as NormalizedRoute;
  },
  async eta(origins: LatLng[], destinations: LatLng[], mode: RouteMode = 'driving') {
    const { data, error } = await supabase.functions.invoke('maps-eta', {
      body: { origins, destinations, mode },
    });
    if (error) throw error;
    if ((data as any)?.error) throw new Error((data as any).error);
    return (data as any).rows as EtaMatrixCell[][];
  },
};