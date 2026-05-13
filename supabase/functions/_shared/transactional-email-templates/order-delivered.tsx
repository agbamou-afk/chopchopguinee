/// <reference types="npm:@types/react@18.3.1" />
import * as React from 'npm:react@18.3.1'
import { CTAButton, EmailLayout, H1, H2, P, StatusBadge, SupportSection, TimelineSection, TransactionCard } from '../email-components.tsx'
import { BRAND, formatDateFr } from '../email-brand.ts'
import type { TemplateEntry } from './registry.ts'

interface Props {
  reference: string
  merchantName?: string
  deliveredAt?: string
  firstName?: string
}

const OrderDeliveredEmail = ({
  reference,
  merchantName = 'Marchand CHOP CHOP',
  deliveredAt = new Date().toISOString(),
  firstName,
}: Props) => (
  <EmailLayout preview={`Commande livrée — ${reference}`}>
    <StatusBadge tone="success">Livraison réussie</StatusBadge>
    <H1>{firstName ? `${firstName}, c'est livré 🎉` : 'Votre commande est livrée 🎉'}</H1>
    <P>Bon appétit&nbsp;! Pensez à noter votre marchand pour aider la communauté.</P>
    <TransactionCard
      title="Récapitulatif"
      rows={[
        { label: 'Référence', value: reference, emphasize: true },
        { label: 'Marchand', value: merchantName },
        { label: 'Livré le', value: formatDateFr(deliveredAt) },
      ]}
    />
    <TimelineSection
      steps={[
        { label: 'Commande passée', done: true },
        { label: 'Préparation', done: true },
        { label: 'En route', done: true },
        { label: 'Livré', done: true, current: true },
      ]}
    />
    <H2>Notez votre commande</H2>
    <P>Votre avis aide à maintenir un service fiable et de qualité partout en Guinée.</P>
    <CTAButton href={`${BRAND.url}/orders/${reference}/rate`}>Laisser un avis</CTAButton>
    <SupportSection />
  </EmailLayout>
)

export const template = {
  component: OrderDeliveredEmail,
  subject: (d: Record<string, any>) => `Commande livrée — ${d.reference}`,
  displayName: 'Commande livrée',
  previewData: {
    reference: 'CC-OD-AB12CD34',
    merchantName: 'Boutique Sankarah',
    deliveredAt: new Date().toISOString(),
    firstName: 'Mariama',
  },
} satisfies TemplateEntry