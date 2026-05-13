/// <reference types="npm:@types/react@18.3.1" />
import * as React from 'npm:react@18.3.1'
import { AmountDisplay, CTAButton, EmailLayout, H1, P, StatusBadge, SupportSection, TransactionCard } from '../email-components.tsx'
import { BRAND, formatDateFr, formatGNF } from '../email-brand.ts'
import type { TemplateEntry } from './registry.ts'

interface Props {
  amountGnf: number
  reference: string
  reason?: string
  originalReference?: string
  occurredAt?: string
  firstName?: string
}

const RefundProcessedEmail = ({
  amountGnf,
  reference,
  reason = 'Remboursement CHOP CHOP',
  originalReference,
  occurredAt = new Date().toISOString(),
  firstName,
}: Props) => (
  <EmailLayout preview={`Remboursement de ${formatGNF(amountGnf)} effectué`}>
    <StatusBadge tone="info">Remboursement effectué</StatusBadge>
    <H1>{firstName ? `Bonjour ${firstName},` : 'Votre remboursement est traité'}</H1>
    <P>
      Le montant a été recrédité sur votre portefeuille CHOP CHOP. Aucune
      action de votre part n'est nécessaire.
    </P>
    <AmountDisplay amount={amountGnf} label="Montant remboursé" tone="positive" />
    <TransactionCard
      title="Détails"
      rows={[
        { label: 'Référence', value: reference, emphasize: true },
        ...(originalReference ? [{ label: 'Transaction d\'origine', value: originalReference }] : []),
        { label: 'Motif', value: reason },
        { label: 'Date', value: formatDateFr(occurredAt) },
      ]}
    />
    <CTAButton href={`${BRAND.url}/wallet`}>Voir mon portefeuille</CTAButton>
    <SupportSection />
  </EmailLayout>
)

export const template = {
  component: RefundProcessedEmail,
  subject: (d: Record<string, any>) => `Remboursement effectué — ${formatGNF(d.amountGnf)}`,
  displayName: 'Remboursement effectué',
  previewData: {
    amountGnf: 25000,
    reference: 'CC-RF-AB99CD11EF',
    originalReference: 'CC-PY-ZZ12YY34',
    reason: 'Course annulée par le chauffeur',
    occurredAt: new Date().toISOString(),
    firstName: 'Mariama',
  },
} satisfies TemplateEntry