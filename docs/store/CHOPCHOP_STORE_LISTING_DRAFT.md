# CHOPCHOP — Store Listing Draft (App Store & Google Play)

French-first, pilot-safe, no overpromising. Keep in sync with
`Privacy.tsx`, `Terms.tsx`, and the Permission Center.

## App name

**CHOPCHOP Guinée**

## Subtitle (App Store, 30 chars)

Transport, repas, marché et paiements

## Short description (Play, 80 chars)

CHOPCHOP réunit Moto, TokTok, repas, marché et ChopWallet pour Conakry.

## Long description

CHOPCHOP est la super-app pensée pour Conakry. Tout ce dont vous avez
besoin au quotidien, regroupé dans une seule application simple et
rapide.

• **Moto et TokTok** — Commandez une course en quelques secondes et
  suivez votre coursier en temps réel.
• **Chop Repas** — Vos plats préférés livrés chauds, depuis les
  restaurants de Conakry.
• **Chop Marché** — Produits frais et boutiques locales livrés à
  votre porte.
• **ChopWallet et ChopPay** — Portefeuille sécurisé pour payer,
  recevoir et envoyer (phase pilote, fonctionnalités étendues à
  venir).
• **Support intégré** — Posez une question ou signalez un souci
  directement depuis l'app.

CHOPCHOP est opéré par CHOP GUINEE LTD à Conakry. Vos données et vos
paiements sont protégés. Vous pouvez gérer vos permissions et
demander la suppression de votre compte à tout moment depuis votre
profil.

## Keywords (App Store, ≤100 chars)

Guinée,Conakry,moto,TokTok,livraison,repas,marché,wallet,paiement,transport,coursier

## Category

- App Store: **Lifestyle** (primary), **Food & Drink** (secondary).
- Play: **Maps & Navigation** or **Lifestyle** (primary), with content
  rating "Everyone".

## URLs

- Marketing / website: https://chopchopguinee.com
- Support: https://chopchopguinee.com/help
- Privacy: https://chopchopguinee.com/privacy
- Terms: https://chopchopguinee.com/terms
- Account deletion request: in-app, Profil → "Demander la suppression
  du compte"

## Contact

- Support email: support@chopchopguinee.com
- Privacy email: privacy@chopchopguinee.com
- Legal entity: CHOP GUINEE LTD, Conakry, République de Guinée

## Pricing

Free. In-app transactions (rides, deliveries, top-ups, marketplace
purchases) are handled through CHOPCHOP's own payment rails and are
NOT in-app purchases (IAP). No subscriptions.

## Native permission copy

Use these exact strings in `Info.plist` / Android manifest.

- **`NSLocationWhenInUseUsageDescription`**
  "CHOPCHOP utilise votre position pour afficher les services proches
  de vous, faciliter les courses et livraisons, et améliorer la
  fiabilité du service."
- **`NSCameraUsageDescription`**
  "La caméra est utilisée pour scanner les QR codes CHOPCHOP."
- **`NSPhotoLibraryUsageDescription`** /
  **`NSPhotoLibraryAddUsageDescription`**
  "Ajoutez des images ou documents lorsque vous choisissez de les
  envoyer."
- **Notifications (iOS prompt + Android 13+ `POST_NOTIFICATIONS`)**
  "Recevez les mises à jour importantes sur vos courses, commandes,
  paiements et demandes support."

**Not requested at launch:** Contacts, Microphone, App Tracking
Transparency, Bluetooth, Calendar, Reminders, Health, Motion.

## What's new (release notes, template)

Première version publique de CHOPCHOP Guinée. Découvrez Moto, TokTok,
Chop Repas, Chop Marché et ChopWallet — la super-app de Conakry.