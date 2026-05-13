/// <reference types="npm:@types/react@18.3.1" />
import * as React from 'npm:react@18.3.1'
import { CTAButton, EmailLayout, H1, H2, P, SupportSection } from '../email-components.tsx'
import { BRAND } from '../email-brand.ts'
import type { TemplateEntry } from './registry.ts'

interface Props { firstName?: string }

const WelcomeEmail = ({ firstName }: Props) => (
  <EmailLayout preview="Bienvenue dans CHOP CHOP">
    <H1>{firstName ? `Bienvenue, ${firstName} 🇬🇳` : 'Bienvenue sur CHOP CHOP 🇬🇳'}</H1>
    <P>
      Votre compte est actif. Vous pouvez désormais commander une moto ou un
      toktok, recharger votre portefeuille auprès d'un agent, payer chez les
      marchands, et explorer le marché local.
    </P>
    <CTAButton href={BRAND.url}>Ouvrir CHOP CHOP</CTAButton>
    <H2>Prochaines étapes</H2>
    <P muted>
      • Configurez votre code PIN portefeuille pour sécuriser vos paiements.<br />
      • Activez WhatsApp pour recevoir vos confirmations en temps réel.<br />
      • Recharger votre portefeuille auprès d'un agent agréé près de chez vous.
    </P>
    <SupportSection />
  </EmailLayout>
)

export const template = {
  component: WelcomeEmail,
  subject: 'Bienvenue sur CHOP CHOP',
  displayName: 'Bienvenue',
  previewData: { firstName: 'Mariama' },
} satisfies TemplateEntry