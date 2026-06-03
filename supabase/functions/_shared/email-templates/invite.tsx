/// <reference types="npm:@types/react@18.3.1" />
import * as React from 'npm:react@18.3.1'
import { CTAButton, EmailLayout, H1, P, SupportSection } from '../email-components.tsx'

interface Props {
  siteName?: string
  siteUrl?: string
  confirmationUrl: string
}

export const InviteEmail = ({ confirmationUrl }: Props) => (
  <EmailLayout preview="Vous êtes invité à rejoindre CHOPCHOP 🇬🇳">
    <H1>Vous êtes invité sur CHOPCHOP</H1>
    <P>
      Vous avez été invité à rejoindre CHOPCHOP. Cliquez sur le bouton
      ci-dessous pour accepter l'invitation et créer votre compte.
    </P>
    <CTAButton href={confirmationUrl}>Accepter l'invitation</CTAButton>
    <P muted>
      Si vous n'attendiez pas cette invitation, ignorez cet e-mail.
    </P>
    <SupportSection />
  </EmailLayout>
)

export default InviteEmail
