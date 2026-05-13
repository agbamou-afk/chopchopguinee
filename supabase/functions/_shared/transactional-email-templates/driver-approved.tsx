/// <reference types="npm:@types/react@18.3.1" />
import * as React from 'npm:react@18.3.1'
import { CTAButton, EmailLayout, H1, H2, P, StatusBadge, SupportSection } from '../email-components.tsx'
import { BRAND } from '../email-brand.ts'
import type { TemplateEntry } from './registry.ts'

interface Props { firstName?: string; vehicleType?: string }

const DriverApprovedEmail = ({ firstName, vehicleType = 'moto' }: Props) => (
  <EmailLayout preview="Votre compte chauffeur CHOP CHOP est approuvé">
    <StatusBadge tone="success">Compte chauffeur activé</StatusBadge>
    <H1>{firstName ? `Bienvenue à bord, ${firstName} 🇬🇳` : 'Bienvenue à bord 🇬🇳'}</H1>
    <P>
      Vos documents ont été vérifiés et approuvés. Votre compte chauffeur
      ({vehicleType}) est désormais actif. Vous pouvez recevoir des courses
      et gagner avec CHOP CHOP.
    </P>
    <CTAButton href={`${BRAND.url}/driver`}>Passer en mode Chauffeur</CTAButton>
    <H2>Bonnes pratiques</H2>
    <P muted>
      • Vérifiez votre solde et vos commissions chaque jour.<br />
      • Gardez votre permis et votre carte grise à jour.<br />
      • Maintenez une note client supérieure à 4,5 ★ pour rester prioritaire.
    </P>
    <SupportSection />
  </EmailLayout>
)

export const template = {
  component: DriverApprovedEmail,
  subject: 'Votre compte chauffeur CHOP CHOP est approuvé',
  displayName: 'Chauffeur approuvé',
  previewData: { firstName: 'Ibrahima', vehicleType: 'moto' },
} satisfies TemplateEntry