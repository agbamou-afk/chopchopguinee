/// <reference types="npm:@types/react@18.3.1" />
import * as React from 'npm:react@18.3.1'
import { AmountDisplay, CTAButton, EmailLayout, H1, P, StatusBadge, SupportSection, TimelineSection, TransactionCard } from '../email-components.tsx'
import { BRAND, formatDateFr, formatGNF } from '../email-brand.ts'
import type { TemplateEntry } from './registry.ts'

interface Props {
  totalGnf: number
  reference: string
  merchantName?: string
  itemCount?: number
  estimatedDelivery?: string
  occurredAt?: string
  firstName?: string
}

const OrderConfirmedEmail = ({
  totalGnf,
  reference,
  merchantName = 'Marchand CHOP CHOP',
  itemCount,
  estimatedDelivery,
  occurredAt = new Date().toISOString(),
  firstName,
}: Props) => (
  <EmailLayout preview={`Commande confirmée — ${reference}`}>
    <StatusBadge tone="success">Commande confirmée</StatusBadge>
    <H1>{firstName ? `Merci, ${firstName} 🇬🇳` : 'Commande confirmée'}</H1>
    <P>Le marchand prépare votre commande. Nous vous tiendrons informé.</P>
    <AmountDisplay amount={totalGnf} label="Total commande" />
    <TransactionCard
      title="Récapitulatif"
      rows={[
        { label: 'Référence', value: reference, emphasize: true },
        { label: 'Marchand', value: merchantName },
        ...(itemCount ? [{ label: 'Articles', value: String(itemCount) }] : []),
        ...(estimatedDelivery ? [{ label: 'Livraison estimée', value: estimatedDelivery }] : []),
        { label: 'Commandé le', value: formatDateFr(occurredAt) },
      ]}
    />
    <TimelineSection
      steps={[
        { label: 'Commande passée', done: true },
        { label: 'Préparation par le marchand', done: false, current: true },
        { label: 'En route', done: false },
        { label: 'Livré', done: false },
      ]}
    />
    <CTAButton href={`${BRAND.url}/orders/${reference}`}>Suivre la commande</CTAButton>
    <SupportSection />
  </EmailLayout>
)

export const template = {
  component: OrderConfirmedEmail,
  subject: (d: Record<string, any>) => `Commande confirmée — ${d.reference}`,
  displayName: 'Commande confirmée',
  previewData: {
    totalGnf: 78500,
    reference: 'CC-OD-AB12CD34',
    merchantName: 'Boutique Sankarah',
    itemCount: 3,
    estimatedDelivery: 'Aujourd\'hui, 17h00–18h00',
    occurredAt: new Date().toISOString(),
    firstName: 'Mariama',
  },
} satisfies TemplateEntry