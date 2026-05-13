/// <reference types="npm:@types/react@18.3.1" />
import * as React from 'npm:react@18.3.1'
import { AmountDisplay, CTAButton, EmailLayout, H1, P, StatusBadge, SupportSection, TransactionCard } from '../email-components.tsx'
import { BRAND, formatDateFr, formatGNF } from '../email-brand.ts'
import type { TemplateEntry } from './registry.ts'

interface Props {
  fareGnf: number
  reference: string
  mode?: string // 'moto' | 'toktok' | 'voiture'
  driverName?: string
  pickup?: string
  destination?: string
  durationMinutes?: number
  distanceKm?: number
  occurredAt?: string
  firstName?: string
}

const modeLabel: Record<string, string> = {
  moto: 'Moto',
  toktok: 'Toktok',
  voiture: 'Voiture',
}

const RideReceiptEmail = ({
  fareGnf,
  reference,
  mode = 'moto',
  driverName = 'Votre chauffeur',
  pickup = '—',
  destination = '—',
  durationMinutes,
  distanceKm,
  occurredAt = new Date().toISOString(),
  firstName,
}: Props) => (
  <EmailLayout preview={`Reçu course ${modeLabel[mode] ?? mode} — ${formatGNF(fareGnf)}`}>
    <StatusBadge tone="success">Course terminée</StatusBadge>
    <H1>{firstName ? `Merci pour la course, ${firstName}` : 'Merci pour la course'}</H1>
    <P>Voici votre reçu CHOP CHOP. Bonne route&nbsp;!</P>
    <AmountDisplay amount={fareGnf} label="Total course" />
    <TransactionCard
      title="Détails du trajet"
      rows={[
        { label: 'Référence', value: reference, emphasize: true },
        { label: 'Mode', value: modeLabel[mode] ?? mode },
        { label: 'Chauffeur', value: driverName },
        { label: 'Départ', value: pickup },
        { label: 'Destination', value: destination },
        ...(distanceKm ? [{ label: 'Distance', value: `${distanceKm.toFixed(1)} km` }] : []),
        ...(durationMinutes ? [{ label: 'Durée', value: `${durationMinutes} min` }] : []),
        { label: 'Date', value: formatDateFr(occurredAt) },
      ]}
    />
    <CTAButton href={`${BRAND.url}/rides`}>Voir mes courses</CTAButton>
    <SupportSection />
  </EmailLayout>
)

export const template = {
  component: RideReceiptEmail,
  subject: (d: Record<string, any>) => `Reçu course — ${formatGNF(d.fareGnf)}`,
  displayName: 'Reçu de course',
  previewData: {
    fareGnf: 18000,
    reference: 'CC-RD-AA11BB22CC',
    mode: 'moto',
    driverName: 'Ibrahima D.',
    pickup: 'Kaloum, Conakry',
    destination: 'Aéroport de Conakry',
    distanceKm: 14.2,
    durationMinutes: 32,
    occurredAt: new Date().toISOString(),
    firstName: 'Mariama',
  },
} satisfies TemplateEntry