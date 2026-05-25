/**
 * CHOPCHOP — Local Conakry gazetteer.
 *
 * Hand-curated reference set of common Conakry districts, neighborhoods,
 * landmarks, KM markers, and transport points. Used to power forgiving
 * pickup/dropoff search BEFORE delegating to an external geocoder.
 *
 * Confidence:
 *   - 'exact'       : coordinates verified to a recognisable point
 *   - 'approximate' : coordinates point to the general area only
 *   - 'district_only': no point coordinates, only district-level grouping
 *
 * IMPORTANT: approximate ≠ exact. Always surface the confidence label so
 * users can correct the pickup pin if needed.
 */

export type PlaceCategory =
  | 'district' | 'neighborhood' | 'market' | 'landmark' | 'hospital'
  | 'school' | 'transport' | 'road' | 'km_marker' | 'airport'
  | 'admin' | 'restaurant' | 'store' | 'other';

export type PlaceConfidence = 'exact' | 'approximate' | 'district_only';

export interface GazetteerPlace {
  id: string;
  name: string;
  aliases: string[];
  district: string | null;   // urban district (Kipé, Bambeto…)
  commune: string | null;    // commune (Ratoma, Matoto…)
  category: PlaceCategory;
  latitude: number | null;
  longitude: number | null;
  confidence: PlaceConfidence;
}

function kmMarker(km: number, lat: number, lng: number): GazetteerPlace {
  return {
    id: `km-${km}`,
    name: `KM ${km}`,
    aliases: [
      `km${km}`, `km ${km}`, `km-${km}`, `k m ${km}`,
      `kilometre ${km}`, `kilomètre ${km}`, `kilometer ${km}`,
      `kilometres ${km}`,
    ],
    district: null,
    commune: km <= 8 ? 'Ratoma' : km <= 20 ? 'Matoto' : null,
    category: 'km_marker',
    latitude: lat,
    longitude: lng,
    confidence: 'approximate',
  };
}

/**
 * Approximate coordinates derived from publicly known landmark positions
 * (Bambeto roundabout, Hamdallaye, Cosa, Kipé, Madina market, Aéroport
 * Gbessia, etc.). Anything not verifiable is marked 'district_only'.
 */
export const CONAKRY_PLACES: GazetteerPlace[] = [
  // --- Communes (administrative) ---
  { id: 'commune-kaloum', name: 'Kaloum', aliases: ['kaloum'], district: null, commune: 'Kaloum', category: 'admin', latitude: 9.5111, longitude: -13.7117, confidence: 'approximate' },
  { id: 'commune-dixinn', name: 'Dixinn', aliases: ['dixinn', 'dixin'], district: null, commune: 'Dixinn', category: 'admin', latitude: 9.5436, longitude: -13.6803, confidence: 'approximate' },
  { id: 'commune-matam', name: 'Matam', aliases: ['matam'], district: null, commune: 'Matam', category: 'admin', latitude: 9.5300, longitude: -13.6750, confidence: 'approximate' },
  { id: 'commune-ratoma', name: 'Ratoma', aliases: ['ratoma'], district: null, commune: 'Ratoma', category: 'admin', latitude: 9.6175, longitude: -13.6300, confidence: 'approximate' },
  { id: 'commune-matoto', name: 'Matoto', aliases: ['matoto'], district: null, commune: 'Matoto', category: 'admin', latitude: 9.5836, longitude: -13.5811, confidence: 'approximate' },

  // --- Neighborhoods (Ratoma corridor) ---
  { id: 'kipe',        name: 'Kipé',       aliases: ['kipe', 'kippe', 'kipé'],            district: 'Kipé',       commune: 'Ratoma', category: 'neighborhood', latitude: 9.6364, longitude: -13.6347, confidence: 'approximate' },
  { id: 'bambeto',     name: 'Bambeto',    aliases: ['bambeto', 'rond-point bambeto'],   district: 'Bambeto',    commune: 'Ratoma', category: 'neighborhood', latitude: 9.6056, longitude: -13.6361, confidence: 'approximate' },
  { id: 'hamdallaye',  name: 'Hamdallaye', aliases: ['hamdallaye', 'hamdalaye', 'hamdalaie', 'rond-point hamdallaye'], district: 'Hamdallaye', commune: 'Ratoma', category: 'neighborhood', latitude: 9.5969, longitude: -13.6464, confidence: 'approximate' },
  { id: 'cosa',        name: 'Cosa',       aliases: ['cosa', 'rond-point cosa'],          district: 'Cosa',       commune: 'Ratoma', category: 'neighborhood', latitude: 9.6225, longitude: -13.6256, confidence: 'approximate' },
  { id: 'lambanyi',    name: 'Lambanyi',   aliases: ['lambanyi', 'lambandji'],            district: 'Lambanyi',   commune: 'Ratoma', category: 'neighborhood', latitude: 9.6478, longitude: -13.6058, confidence: 'approximate' },
  { id: 'sonfonia',    name: 'Sonfonia',   aliases: ['sonfonia'],                         district: 'Sonfonia',   commune: 'Ratoma', category: 'neighborhood', latitude: 9.6603, longitude: -13.5919, confidence: 'approximate' },
  { id: 'nongo',       name: 'Nongo',      aliases: ['nongo'],                            district: 'Nongo',      commune: 'Ratoma', category: 'neighborhood', latitude: 9.6611, longitude: -13.6358, confidence: 'approximate' },
  { id: 'taouyah',     name: 'Taouyah',    aliases: ['taouyah', 'taouya'],                district: 'Taouyah',    commune: 'Ratoma', category: 'neighborhood', latitude: 9.5961, longitude: -13.6700, confidence: 'approximate' },
  { id: 'kaporo',      name: 'Kaporo',     aliases: ['kaporo'],                           district: 'Kaporo',     commune: 'Ratoma', category: 'neighborhood', latitude: 9.6469, longitude: -13.6453, confidence: 'approximate' },
  { id: 'wanindara',   name: 'Wanindara',  aliases: ['wanindara'],                        district: 'Wanindara',  commune: 'Ratoma', category: 'neighborhood', latitude: 9.6661, longitude: -13.6094, confidence: 'approximate' },
  { id: 'simbaya',     name: 'Simbaya',    aliases: ['simbaya'],                          district: 'Simbaya',    commune: 'Matoto', category: 'neighborhood', latitude: 9.6022, longitude: -13.5719, confidence: 'approximate' },
  { id: 'enta',        name: 'Enta',       aliases: ['enta'],                             district: 'Enta',       commune: 'Matoto', category: 'neighborhood', latitude: 9.5839, longitude: -13.5825, confidence: 'approximate' },
  { id: 'camayenne',   name: 'Camayenne',  aliases: ['camayenne'],                        district: 'Camayenne',  commune: 'Dixinn', category: 'neighborhood', latitude: 9.5450, longitude: -13.6864, confidence: 'approximate' },
  { id: 'miniere',     name: 'Minière',    aliases: ['miniere', 'minière'],               district: 'Minière',    commune: 'Dixinn', category: 'neighborhood', latitude: 9.5469, longitude: -13.6700, confidence: 'approximate' },
  { id: 'bellevue',    name: 'Bellevue',   aliases: ['bellevue', 'belle vue', 'belle-vue'], district: 'Bellevue', commune: 'Dixinn', category: 'neighborhood', latitude: 9.5283, longitude: -13.6839, confidence: 'approximate' },
  { id: 'madina',      name: 'Madina',     aliases: ['madina', 'marché madina', 'marche madina'], district: 'Madina', commune: 'Matam', category: 'neighborhood', latitude: 9.5300, longitude: -13.6536, confidence: 'approximate' },
  { id: 'coleah',      name: 'Coléah',     aliases: ['coleah', 'coléah'],                 district: 'Coléah',     commune: 'Matam',  category: 'neighborhood', latitude: 9.5197, longitude: -13.6817, confidence: 'approximate' },
  { id: 'almamya',     name: 'Almamya',    aliases: ['almamya'],                          district: 'Almamya',    commune: 'Kaloum', category: 'neighborhood', latitude: 9.5083, longitude: -13.7050, confidence: 'approximate' },
  { id: 'boulbinet',   name: 'Boulbinet',  aliases: ['boulbinet'],                        district: 'Boulbinet',  commune: 'Kaloum', category: 'neighborhood', latitude: 9.5072, longitude: -13.7222, confidence: 'approximate' },

  // --- KM markers along Route Le Prince / autoroute ---
  kmMarker(5,  9.5708, -13.6611),
  kmMarker(10, 9.5872, -13.6342),
  kmMarker(13, 9.5944, -13.6217),
  kmMarker(36, 9.6731, -13.5217),
  kmMarker(54, 9.7517, -13.4533),

  // --- Transport / landmarks ---
  { id: 'aeroport-gbessia', name: 'Aéroport International de Conakry', aliases: ['aeroport', 'aéroport', 'aeroport gbessia', 'gbessia', 'airport', 'conakry airport', 'cky'], district: 'Gbessia', commune: 'Matoto', category: 'airport', latitude: 9.5770, longitude: -13.6120, confidence: 'approximate' },
  { id: 'donka',           name: 'Hôpital Donka',     aliases: ['donka', 'hopital donka', 'hôpital donka'], district: 'Donka', commune: 'Dixinn', category: 'hospital', latitude: 9.5453, longitude: -13.6878, confidence: 'approximate' },
  { id: 'ignace-deen',     name: 'Hôpital Ignace Deen', aliases: ['ignace deen', 'ignace-deen'], district: 'Kaloum', commune: 'Kaloum', category: 'hospital', latitude: 9.5117, longitude: -13.7128, confidence: 'approximate' },
  { id: 'marche-madina',   name: 'Marché Madina',     aliases: ['marche madina', 'marché madina'], district: 'Madina', commune: 'Matam', category: 'market', latitude: 9.5300, longitude: -13.6536, confidence: 'approximate' },
  { id: 'marche-niger',    name: 'Marché Niger',      aliases: ['marche niger', 'marché niger'], district: 'Kaloum', commune: 'Kaloum', category: 'market', latitude: 9.5097, longitude: -13.7144, confidence: 'approximate' },
  { id: 'marche-taouyah',  name: 'Marché Taouyah',    aliases: ['marche taouyah', 'marché taouyah'], district: 'Taouyah', commune: 'Ratoma', category: 'market', latitude: 9.5961, longitude: -13.6700, confidence: 'approximate' },
  { id: 'stade-28-sept',   name: 'Stade du 28 Septembre', aliases: ['stade 28 septembre', 'stade du 28 septembre', '28 septembre'], district: 'Matam', commune: 'Matam', category: 'landmark', latitude: 9.5269, longitude: -13.6736, confidence: 'approximate' },
  { id: 'palais-peuple',   name: 'Palais du Peuple',  aliases: ['palais du peuple', 'palais peuple'], district: 'Kaloum', commune: 'Kaloum', category: 'landmark', latitude: 9.5106, longitude: -13.7044, confidence: 'approximate' },
  { id: 'gamal-univ',      name: 'Université Gamal Abdel Nasser', aliases: ['gamal', 'universite gamal', 'université gamal', 'uganc'], district: 'Dixinn', commune: 'Dixinn', category: 'school', latitude: 9.5394, longitude: -13.6739, confidence: 'approximate' },
  { id: 'port-autonome',   name: 'Port Autonome de Conakry', aliases: ['port autonome', 'port de conakry'], district: 'Kaloum', commune: 'Kaloum', category: 'transport', latitude: 9.5025, longitude: -13.7167, confidence: 'approximate' },
];