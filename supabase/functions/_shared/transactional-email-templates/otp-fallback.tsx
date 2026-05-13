/// <reference types="npm:@types/react@18.3.1" />
import * as React from 'npm:react@18.3.1'
import { EmailLayout, H1, H2, P, SupportSection } from '../email-components.tsx'
import { COLORS, FONT_STACK, RADIUS } from '../email-brand.ts'
import type { TemplateEntry } from './registry.ts'

interface Props { code: string; expiresInMinutes?: number }

const OtpFallbackEmail = ({ code, expiresInMinutes = 10 }: Props) => (
  <EmailLayout preview={`Votre code de vérification CHOP CHOP : ${code}`}>
    <H1>Votre code de vérification</H1>
    <P>
      Le SMS n'a pas pu être livré sur votre téléphone. Utilisez le code
      ci-dessous pour vous connecter à CHOP CHOP.
    </P>
    <div style={codeBox}>{code}</div>
    <P muted>
      Ce code expire dans {expiresInMinutes} minutes. Ne le partagez avec
      personne, pas même un agent CHOP CHOP.
    </P>
    <H2>Vous n'avez rien demandé&nbsp;?</H2>
    <P muted>
      Ignorez cet e-mail. Aucune action ne sera effectuée tant que le code
      n'est pas utilisé.
    </P>
    <SupportSection />
  </EmailLayout>
)

const codeBox: React.CSSProperties = {
  backgroundColor: COLORS.surfaceMuted,
  border: `1px solid ${COLORS.border}`,
  borderRadius: RADIUS.md,
  padding: '18px 24px',
  margin: '12px 0 18px',
  fontFamily: FONT_STACK,
  fontSize: '32px',
  fontWeight: 700,
  letterSpacing: '0.4em',
  textAlign: 'center',
  color: COLORS.text,
}

export const template = {
  component: OtpFallbackEmail,
  subject: (d: Record<string, any>) => `Votre code CHOP CHOP : ${d.code}`,
  displayName: 'Code OTP (e-mail de secours)',
  previewData: { code: '482913', expiresInMinutes: 10 },
} satisfies TemplateEntry