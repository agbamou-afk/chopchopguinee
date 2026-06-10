/**
 * Phase 1 — Selectable product categories for Marché merchants.
 * Editable later in MerchantHub > Boutique.
 */
export const MERCHANT_PRODUCT_CATEGORIES: { id: string; label: string }[] = [
  { id: "epicerie", label: "Épicerie" },
  { id: "produits_frais", label: "Produits frais" },
  { id: "boissons", label: "Boissons" },
  { id: "cosmetiques", label: "Cosmétiques" },
  { id: "telephones", label: "Téléphones / accessoires" },
  { id: "mode", label: "Mode" },
  { id: "quincaillerie", label: "Quincaillerie" },
  { id: "auto_moto", label: "Pièces auto / moto" },
  { id: "pharmacie", label: "Pharmacie / santé" },
  { id: "services", label: "Services" },
  { id: "autre", label: "Autre" },
];

export function labelForCategory(id: string): string {
  return MERCHANT_PRODUCT_CATEGORIES.find((c) => c.id === id)?.label ?? id;
}