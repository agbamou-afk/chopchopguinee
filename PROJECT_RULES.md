# CHOP CHOP — Project Rules

## Product vision
CHOP CHOP is the commercial operating layer for urban Guinea: a super-app that unifies ride-hailing (Moto, TokTok), food delivery (Repas), peer-to-peer commerce (Marché), wallet & P2P transfers, and QR scanning into a single mobile experience tailored to West African urban behavior.

## Legal & naming
- Legal entity: **CHOP GUINEE LTD**
- Display brand: **CHOP CHOP** (or short **CHOP**)
- Slogan (exact): **Tout. Partout. Pour Tous.**
- Currency: **GNF** (Guinean Franc), formatted with spaces: `2 500 000 GNF`
- **Never** write "Choper", "ChopChop", "Chop-Chop", or translate the slogan.

## Visual identity
- Inspired by the Guinean flag: emerald green, gold/yellow, red
- Plus neutral black, white, light gray
- Plus muted variants of green, yellow, red for surfaces & states
- Feel: modern, optimistic, local, social, useful, human — never corporate or sterile

## Dual-role architecture
Clients and drivers share a single interface controlled by a global mode toggle. Driver mode reuses the same primitives but recolors header context and swaps tab labels.

## Engineering rules
1. **Never hardcode colors** in components (`text-white`, `bg-black`, hex). Always use semantic tokens defined in `src/index.css` + `tailwind.config.ts`.
2. **Never edit** `src/integrations/supabase/{client,types}.ts` or `.env`.
3. **Roles** live in `user_roles` table, never on `profiles`.
4. **No backend code** in the client repo — use Supabase edge functions for server logic.
5. **Auth-gating:** browse is public for Home + Marché; transactional/personal actions require auth via `useAuthGuard().requireAuth()`.
6. **No redesign without request.** Visual refactors must be scoped, additive, and approved phase-by-phase. Do not redesign components the user did not ask about.
7. **Mobile-first:** target 390×844 first; scale up gracefully.
8. **All money** rendered through `formatGNF()` from `src/lib/format.ts`.

## Tone of voice (FR)
- Tutoiement chaleureux mais respectueux
- Phrases courtes, mots simples, pas de jargon
- Ex: "Bonjour, Antoine 👋", "Recharger", "Faire livrer", "Toujours disponible ?"