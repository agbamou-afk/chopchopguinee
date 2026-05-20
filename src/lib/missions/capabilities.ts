export type DriverCapability =
  | "rides_moto"
  | "rides_toktok"
  | "repas_delivery"
  | "marche_delivery"
  | "package_delivery";

export const CAPABILITY_LABEL: Record<DriverCapability, string> = {
  rides_moto: "Moto",
  rides_toktok: "TokTok",
  repas_delivery: "Livraison Repas",
  marche_delivery: "Livraison Marché",
  package_delivery: "Colis",
};

export const ALL_CAPABILITIES: DriverCapability[] = [
  "rides_moto",
  "rides_toktok",
  "repas_delivery",
  "marche_delivery",
  "package_delivery",
];

export function hasCapability(
  list: string[] | null | undefined,
  cap: DriverCapability,
): boolean {
  return Array.isArray(list) && list.includes(cap);
}