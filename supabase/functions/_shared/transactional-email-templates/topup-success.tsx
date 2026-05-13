/// <reference types="npm:@types/react@18.3.1" />
import * as React from 'npm:react@18.3.1'
import { AmountDisplay, CTAButton, EmailLayout, H1, P, StatusBadge, SupportSection, TransactionCard } from '../email-components.tsx'
import { BRAND, formatDateFr, formatGNF } from '../email-brand.ts'
import type { TemplateEntry } from './registry.ts'

interface Props {
  amountGnf: number
  reference: string
  agentName?: string
  agentLocation?: string
  newBalanceGnf?: number
  occurredAt?: string
  firstName?: string
}

const TopupSuccessEmail = ({
  amountGnf,
  reference,
  agentName = 'Agent CHOP CHOP',
  agentLocation,
  newBalanceGnf,
  occurredAt = new Date().toISOString(),
  firstName,
}: Props) => (
  <EmailLayout preview={`Recharge de ${formatGNF(amountGnf)} confirmée`}>
    <StatusBadge tone="success">Recharge confirmée</StatusBadge>
    <H1>{firstName ? `Merci, ${firstName} 🇬🇳` : 'Recharge confirmée 🇬🇳'}</H1>
    <P>
      Votre portefeuille CHOP CHOP a été rechargé avec succès. Vous pouvez
      désormais payer vos courses, commandes et marchands favoris.
    </P>
    <AmountDisplay amount={amountGnf} label="Montant rechargé" tone="positive" />
    <TransactionCard
      title="Détails de la transaction"
      rows={[
        { label: 'Référence', value: reference, emphasize: true },
        { label: 'Agent', value: agentName },
        ...(agentLocation ? [{ label: 'Lieu', value: agentLocation }] : []),
        { label: 'Date', value: formatDateFr(occurredAt) },
        ...(typeof newBalanceGnf === 'number'
          ? [{ label: 'Nouveau solde', value: formatGNF(newBalanceGnf), emphasize: true }]
          : []),
      ]}
    />
    <CTAButton href={`${BRAND.url}/wallet`}>Voir mon portefeuille</CTAButton>
    <SupportSection />
  </EmailLayout>
)

export const template = {
  component: TopupSuccessEmail,
  subject: (d: Record<string, any>) => `Recharge confirmée — ${formatGNF(d.amountGnf)}`,
  displayName: 'Recharge confirmée',
  previewData: {
    amountGnf: 150000,
    reference: 'CC-TX-AB12CD34EF',
    agentName: 'Madame Bah',
    agentLocation: 'Marché Madina, Conakry',
    newBalanceGnf: 285000,
    occurredAt: new Date().toISOString(),
    firstName: 'Mariama',
  },
} satisfies TemplateEntry