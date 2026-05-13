/// <reference types="npm:@types/react@18.3.1" />
import * as React from 'npm:react@18.3.1'
import { CTAButton, EmailLayout, H1, H2, P, StatusBadge, SupportSection, TransactionCard } from '../email-components.tsx'
import { BRAND, formatDateFr } from '../email-brand.ts'
import type { TemplateEntry } from './registry.ts'

interface Props {
  eventType?: string
  occurredAt?: string
  device?: string
  location?: string
  ipAddress?: string
  firstName?: string
}

const SecurityAlertEmail = ({
  eventType = 'Nouvelle connexion détectée',
  occurredAt = new Date().toISOString(),
  device = 'Appareil inconnu',
  location = 'Conakry, Guinée',
  ipAddress = '—',
  firstName,
}: Props) => (
  <EmailLayout preview={`Alerte sécurité CHOP CHOP — ${eventType}`}>
    <StatusBadge tone="warning">Alerte sécurité</StatusBadge>
    <H1>{firstName ? `Bonjour ${firstName},` : 'Activité détectée sur votre compte'}</H1>
    <P>
      Nous avons détecté une activité importante sur votre compte CHOP CHOP.
      Si c'est bien vous, vous pouvez ignorer cet e-mail.
    </P>
    <TransactionCard
      title="Détails de l'événement"
      rows={[
        { label: 'Événement', value: eventType, emphasize: true },
        { label: 'Quand', value: formatDateFr(occurredAt) },
        { label: 'Appareil', value: device },
        { label: 'Localisation', value: location },
        { label: 'Adresse IP', value: ipAddress },
      ]}
    />
    <H2>Ce n'était pas vous&nbsp;?</H2>
    <P>
      Sécurisez votre compte immédiatement&nbsp;: changez votre code PIN
      portefeuille et déconnectez tous les appareils.
    </P>
    <CTAButton href={`${BRAND.url}/security`}>Sécuriser mon compte</CTAButton>
    <SupportSection />
  </EmailLayout>
)

export const template = {
  component: SecurityAlertEmail,
  subject: (d: Record<string, any>) => `Alerte sécurité — ${d.eventType ?? 'Activité de compte'}`,
  displayName: 'Alerte sécurité',
  previewData: {
    eventType: 'Nouvelle connexion détectée',
    occurredAt: new Date().toISOString(),
    device: 'iPhone 15 — Safari',
    location: 'Conakry, Guinée',
    ipAddress: '102.176.0.1',
    firstName: 'Mariama',
  },
} satisfies TemplateEntry