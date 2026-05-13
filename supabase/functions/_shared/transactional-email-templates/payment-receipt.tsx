/// <reference types="npm:@types/react@18.3.1" />
import * as React from 'npm:react@18.3.1'
import { AmountDisplay, CTAButton, EmailLayout, H1, P, StatusBadge, SupportSection, TransactionCard } from '../email-components.tsx'
import { BRAND, formatDateFr, formatGNF } from '../email-brand.ts'
import type { TemplateEntry } from './registry.ts'

interface Props {
  amountGnf: number
  reference: string
  merchantName?: string
  paymentMethod?: string
  occurredAt?: string
  firstName?: string
}

const PaymentReceiptEmail = ({
  amountGnf,
  reference,
  merchantName = 'Marchand CHOP CHOP',
  paymentMethod = 'Portefeuille CHOP CHOP',
  occurredAt = new Date().toISOString(),
  firstName,
}: Props) => (
  <EmailLayout preview={`Reçu de paiement — ${formatGNF(amountGnf)}`}>
    <StatusBadge tone="success">Paiement réussi</StatusBadge>
    <H1>{firstName ? `Merci, ${firstName}` : 'Paiement confirmé'}</H1>
    <P>Voici votre reçu officiel CHOP CHOP. Conservez-le pour vos archives.</P>
    <AmountDisplay amount={amountGnf} label="Montant payé" />
    <TransactionCard
      title="Reçu"
      rows={[
        { label: 'Référence', value: reference, emphasize: true },
        { label: 'Marchand', value: merchantName },
        { label: 'Méthode', value: paymentMethod },
        { label: 'Date', value: formatDateFr(occurredAt) },
      ]}
    />
    <CTAButton href={`${BRAND.url}/wallet/transactions`}>Voir l'historique</CTAButton>
    <SupportSection />
  </EmailLayout>
)

export const template = {
  component: PaymentReceiptEmail,
  subject: (d: Record<string, any>) => `Reçu CHOP CHOP — ${formatGNF(d.amountGnf)}`,
  displayName: 'Reçu de paiement',
  previewData: {
    amountGnf: 45000,
    reference: 'CC-PY-XY99ZZ22AB',
    merchantName: 'Boutique Sankarah',
    paymentMethod: 'Portefeuille CHOP CHOP',
    occurredAt: new Date().toISOString(),
    firstName: 'Mariama',
  },
} satisfies TemplateEntry