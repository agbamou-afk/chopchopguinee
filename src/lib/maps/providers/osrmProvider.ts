import type { RouteProvider } from './types';

export const osrmProvider: RouteProvider = {
  name: 'osrm',
  async route() { throw new Error('OSRM provider not configured'); },
  async eta() { throw new Error('OSRM provider not configured'); },
};