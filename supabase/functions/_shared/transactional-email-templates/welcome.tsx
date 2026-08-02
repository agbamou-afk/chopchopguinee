/// <reference types="npm:@types/react@18.3.1" />
import * as React from 'npm:react@18.3.1'
import { CTAButton, EmailLayout, H1, H2, P, SupportSection } from '../email-components.tsx'
import { BRAND } from '../email-brand.ts'
import type { TemplateEntry } from './registry.ts'

interface Props { firstName?: string }

const WelcomeEmail = ({ firstName }: Props) => (
  <EmailLayout preview="Bienvenue dans CHOPCHOP">
    <H1>{firstName ? `Bienvenue, ${firstName} 🇬🇳` : 'Bienvenue sur CHOPCHOP 🇬🇳'}</H1>
    <P>
      Votre compte est actif, aucune vérification supplémentaire n'est requise
      pour commencer. Vous pouvez commander une moto ou un toktok, commander un
      repas, explorer le marché local et payer vos courses avec Orange Money.
    </P>
    <CTAButton href={BRAND.url}>Ouvrir CHOPCHOP</CTAButton>
    <H2>Prochaines étapes</H2>
    <P muted>
      • Complétez votre profil (nom et numéro) pour des courses plus rapides.<br />
      • Préparez votre compte Orange Money : les paiements sont vérifiés
      manuellement par notre équipe.<br />
      • Activez WhatsApp pour recevoir vos confirmations en temps réel.
    </P>
    <H2>Sécurité</H2>
    <P muted>
      CHOPCHOP ne vous demandera jamais votre mot de passe, votre code PIN ni un
      code Orange Money par email ou par téléphone. Si vous n'êtes pas à
      l'origine de cette inscription, contactez-nous immédiatement.
    </P>
    <SupportSection />
  </EmailLayout>
)

export const template = {
  component: WelcomeEmail,
  subject: 'Bienvenue sur CHOPCHOP',
  displayName: 'Bienvenue',
  previewData: { firstName: 'Mariama' },
} satisfies TemplateEntry