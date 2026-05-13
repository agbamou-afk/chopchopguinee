# CHOP CHOP — Field Testing Checklist (Conakry)

Use the floating **Beaker** button (bottom-right) to log checkpoints, notes
and FPS samples while in the field. The panel is auto-mounted in dev and on
any URL containing `?field=1`.

## Test loop (≈30 min)

1. **Kaloum (centre admin)** — pickup → Madina, moto.
2. **Madina marché** — saved place "Travail", livraison vers Ratoma.
3. **Bambeto rond-point** — toktok 3 passagers vers Cosa.
4. **Kipé résidence** — repas commande depuis Le Damier.
5. **Aéroport Gbessia** — long trajet vers Kaloum, vérifier ETA.
6. **Cosa carrefour** — annulation côté chauffeur, ré-affectation.

## QA must-pass

- GPS autorisé, précision < 50 m
- Carte chargée < 3 s sur 4G modeste
- Marqueur chauffeur **glisse** entre les pings (pas de saut)
- ETA cohérent ±2 min vs Google Maps
- Itinéraire évite zones inaccessibles (marché Madina interne)
- Re-centrage automatique après scroll utilisateur
- Mode hors-ligne : bandeau visible, pas de crash
- Bouton « Appeler chauffeur » fonctionne (tel:)
- Annulation côté client rembourse correctement

## Réseau / device

- Tester sur Android entry-level (Tecno / Itel) ET iPhone milieu de gamme.
- Couper la 4G en plein trajet pour vérifier la dégradation gracieuse.
- Vérifier comportement sous batterie économiseur.

## Données collectées

Chaque checkpoint envoie un événement `field.test.checkpoint` avec :
`{ checkpoint, coords, fps }`. Les notes envoient `field.test.note`.
Les sessions sont bornées par `field.test.started` / `field.test.completed`.

## Bugs critiques à remonter immédiatement

- Marqueur chauffeur disparaît / téléporte
- ETA négatif ou > 60 min sur trajet local
- Crash carte / écran blanc
- Paiement débité sans course
- GPS bloqué après refus initial (impossible de réessayer)