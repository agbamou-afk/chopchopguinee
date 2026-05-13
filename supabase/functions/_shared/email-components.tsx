/// <reference types="npm:@types/react@18.3.1" />

// CHOP CHOP — reusable React Email components, branded.
// Used by every auth + transactional template so the look stays consistent.

import * as React from 'npm:react@18.3.1'
import {
  Body,
  Button,
  Container,
  Head,
  Heading,
  Hr,
  Html,
  Link,
  Preview,
  Section,
  Text,
} from 'npm:@react-email/components@0.0.22'
import { BRAND, COLORS, FONT_STACK, RADIUS, formatGNF } from './email-brand.ts'

// ---------- Layout ----------

interface EmailLayoutProps {
  preview: string
  children: React.ReactNode
  // Set to false for marketing emails so the unsubscribe footer reads correctly
  transactional?: boolean
}

export const EmailLayout: React.FC<EmailLayoutProps> = ({
  preview,
  children,
  transactional = true,
}) => (
  <Html lang="fr" dir="ltr">
    <Head />
    <Preview>{preview}</Preview>
    <Body style={bodyStyle}>
      <Container style={outerContainer}>
        <BrandHeader />
        <Container style={card}>{children}</Container>
        <BrandFooter transactional={transactional} />
      </Container>
    </Body>
  </Html>
)

// ---------- Header ----------

export const BrandHeader: React.FC = () => (
  <Section style={headerSection}>
    <table cellPadding={0} cellSpacing={0} border={0} style={{ width: '100%' }}>
      <tbody>
        <tr>
          <td style={logoCell}>
            <span style={logoMark}>CC</span>
            <span style={logoWord}>CHOP&nbsp;CHOP</span>
          </td>
        </tr>
      </tbody>
    </table>
  </Section>
)

// ---------- Footer ----------

export const BrandFooter: React.FC<{ transactional: boolean }> = ({
  transactional,
}) => (
  <Section style={footerSection}>
    <Text style={footerTagline}>{BRAND.tagline}</Text>
    <Text style={footerLinks}>
      <Link href={`${BRAND.url}/help`} style={footerLink}>
        Aide
      </Link>
      {' · '}
      <Link href={`mailto:${BRAND.supportEmail}`} style={footerLink}>
        Support
      </Link>
      {' · '}
      <Link href={`${BRAND.url}/legal`} style={footerLink}>
        Mentions légales
      </Link>
    </Text>
    <Text style={footerLegal}>
      © {new Date().getFullYear()} {BRAND.legalName} — {BRAND.address}
    </Text>
    {!transactional && (
      <Text style={footerLegal}>
        Vous recevez cet e-mail car vous êtes abonné aux communications {BRAND.name}.
      </Text>
    )}
  </Section>
)

// ---------- Buttons ----------

export const CTAButton: React.FC<{ href: string; children: React.ReactNode }> = ({
  href,
  children,
}) => (
  <Button href={href} style={primaryButton}>
    {children}
  </Button>
)

// ---------- Status Badge ----------

type StatusTone = 'success' | 'warning' | 'error' | 'info' | 'neutral'

export const StatusBadge: React.FC<{
  tone: StatusTone
  children: React.ReactNode
}> = ({ tone, children }) => {
  const tones: Record<StatusTone, { bg: string; fg: string }> = {
    success: { bg: COLORS.successBg, fg: COLORS.successFg },
    warning: { bg: COLORS.warningBg, fg: COLORS.warningFg },
    error: { bg: COLORS.errorBg, fg: COLORS.errorFg },
    info: { bg: COLORS.infoBg, fg: COLORS.infoFg },
    neutral: { bg: COLORS.surfaceMuted, fg: COLORS.textMuted },
  }
  const t = tones[tone]
  return (
    <span
      style={{
        display: 'inline-block',
        padding: '4px 10px',
        backgroundColor: t.bg,
        color: t.fg,
        borderRadius: '999px',
        fontSize: '12px',
        fontWeight: 600,
        letterSpacing: '0.02em',
        textTransform: 'uppercase',
      }}
    >
      {children}
    </span>
  )
}

// ---------- Amount Display ----------

export const AmountDisplay: React.FC<{
  amount: number | string
  label?: string
  tone?: 'positive' | 'negative' | 'neutral'
}> = ({ amount, label, tone = 'neutral' }) => {
  const colorMap = {
    positive: COLORS.successFg,
    negative: COLORS.errorFg,
    neutral: COLORS.text,
  }
  return (
    <Section style={{ margin: '0 0 16px' }}>
      {label && <Text style={amountLabel}>{label}</Text>}
      <Text style={{ ...amountValue, color: colorMap[tone] }}>
        {formatGNF(typeof amount === 'string' ? Number(amount) : amount)}
      </Text>
    </Section>
  )
}

// ---------- Transaction Card ----------

export interface TransactionRow {
  label: string
  value: string | number
  emphasize?: boolean
}

export const TransactionCard: React.FC<{
  rows: TransactionRow[]
  title?: string
}> = ({ rows, title }) => (
  <Section style={txCard}>
    {title && <Text style={txCardTitle}>{title}</Text>}
    <table cellPadding={0} cellSpacing={0} border={0} style={{ width: '100%' }}>
      <tbody>
        {rows.map((r, i) => (
          <tr key={i}>
            <td style={txRowLabel}>{r.label}</td>
            <td
              style={{
                ...txRowValue,
                fontWeight: r.emphasize ? 700 : 500,
                color: r.emphasize ? COLORS.text : COLORS.textMuted,
              }}
            >
              {r.value}
            </td>
          </tr>
        ))}
      </tbody>
    </table>
  </Section>
)

// ---------- Timeline ----------

export interface TimelineStep {
  label: string
  done: boolean
  current?: boolean
}

export const TimelineSection: React.FC<{ steps: TimelineStep[] }> = ({ steps }) => (
  <Section style={{ margin: '8px 0 20px' }}>
    {steps.map((s, i) => (
      <table key={i} cellPadding={0} cellSpacing={0} border={0} style={{ width: '100%', marginBottom: '6px' }}>
        <tbody>
          <tr>
            <td style={{ width: '24px', verticalAlign: 'middle' }}>
              <span
                style={{
                  display: 'inline-block',
                  width: '14px',
                  height: '14px',
                  borderRadius: '999px',
                  backgroundColor: s.done ? COLORS.green : COLORS.surfaceMuted,
                  border: s.current ? `2px solid ${COLORS.gold}` : 'none',
                }}
              />
            </td>
            <td style={{ verticalAlign: 'middle' }}>
              <Text
                style={{
                  margin: 0,
                  fontSize: '14px',
                  color: s.done ? COLORS.text : COLORS.textMuted,
                  fontWeight: s.current ? 600 : 400,
                }}
              >
                {s.label}
              </Text>
            </td>
          </tr>
        </tbody>
      </table>
    ))}
  </Section>
)

// ---------- Support Section ----------

export const SupportSection: React.FC = () => (
  <Section style={supportBox}>
    <Text style={supportText}>
      Besoin d'aide ? Écrivez-nous à{' '}
      <Link href={`mailto:${BRAND.supportEmail}`} style={inlineLink}>
        {BRAND.supportEmail}
      </Link>{' '}
      ou consultez{' '}
      <Link href={`${BRAND.url}/help`} style={inlineLink}>
        notre centre d'aide
      </Link>
      .
    </Text>
  </Section>
)

// ---------- Generic Heading + Text re-exports for templates ----------

export const H1: React.FC<{ children: React.ReactNode; style?: React.CSSProperties }> = ({ children, style }) => (
  <Heading style={{ ...h1, ...(style ?? {}) }}>{children}</Heading>
)

export const H2: React.FC<{ children: React.ReactNode; style?: React.CSSProperties }> = ({ children, style }) => (
  <Heading as="h2" style={{ ...h2, ...(style ?? {}) }}>
    {children}
  </Heading>
)

export const P: React.FC<{ children: React.ReactNode; muted?: boolean }> = ({
  children,
  muted,
}) => <Text style={muted ? pMuted : p}>{children}</Text>

export const Divider: React.FC = () => <Hr style={hr} />

// ---------- Styles ----------

const bodyStyle: React.CSSProperties = {
  backgroundColor: '#ffffff',
  margin: 0,
  padding: 0,
  fontFamily: FONT_STACK,
  color: COLORS.text,
  WebkitFontSmoothing: 'antialiased' as const,
}

const outerContainer: React.CSSProperties = {
  width: '100%',
  maxWidth: '560px',
  margin: '0 auto',
  padding: '24px 16px',
  backgroundColor: '#ffffff',
}

const card: React.CSSProperties = {
  backgroundColor: COLORS.surface,
  border: `1px solid ${COLORS.border}`,
  borderRadius: RADIUS.lg,
  padding: '28px 24px',
  margin: '12px 0',
}

const headerSection: React.CSSProperties = {
  padding: '4px 4px 8px',
}

const logoCell: React.CSSProperties = {
  padding: '4px 0',
  verticalAlign: 'middle',
}

const logoMark: React.CSSProperties = {
  display: 'inline-block',
  width: '36px',
  height: '36px',
  lineHeight: '36px',
  textAlign: 'center',
  borderRadius: '10px',
  backgroundColor: COLORS.green,
  color: '#ffffff',
  fontWeight: 800,
  fontSize: '15px',
  letterSpacing: '0.02em',
  marginRight: '10px',
  verticalAlign: 'middle',
  fontFamily: FONT_STACK,
}

const logoWord: React.CSSProperties = {
  fontSize: '16px',
  fontWeight: 700,
  letterSpacing: '0.06em',
  color: COLORS.text,
  verticalAlign: 'middle',
  fontFamily: FONT_STACK,
}

const footerSection: React.CSSProperties = {
  padding: '16px 4px 4px',
  textAlign: 'center',
}

const footerTagline: React.CSSProperties = {
  fontSize: '12px',
  color: COLORS.textMuted,
  margin: '0 0 8px',
  lineHeight: 1.5,
}

const footerLinks: React.CSSProperties = {
  fontSize: '12px',
  color: COLORS.textMuted,
  margin: '0 0 8px',
}

const footerLink: React.CSSProperties = {
  color: COLORS.textMuted,
  textDecoration: 'underline',
}

const footerLegal: React.CSSProperties = {
  fontSize: '11px',
  color: COLORS.textFaint,
  margin: '4px 0 0',
}

const primaryButton: React.CSSProperties = {
  backgroundColor: COLORS.green,
  color: '#ffffff',
  fontSize: '15px',
  fontWeight: 600,
  borderRadius: RADIUS.md,
  padding: '14px 22px',
  textDecoration: 'none',
  display: 'inline-block',
  fontFamily: FONT_STACK,
}

const txCard: React.CSSProperties = {
  backgroundColor: '#ffffff',
  border: `1px solid ${COLORS.border}`,
  borderRadius: RADIUS.md,
  padding: '16px 18px',
  margin: '8px 0 20px',
}

const txCardTitle: React.CSSProperties = {
  fontSize: '12px',
  fontWeight: 600,
  color: COLORS.textMuted,
  textTransform: 'uppercase',
  letterSpacing: '0.06em',
  margin: '0 0 10px',
}

const txRowLabel: React.CSSProperties = {
  padding: '6px 0',
  fontSize: '13px',
  color: COLORS.textMuted,
  width: '50%',
}

const txRowValue: React.CSSProperties = {
  padding: '6px 0',
  fontSize: '13px',
  textAlign: 'right',
}

const supportBox: React.CSSProperties = {
  backgroundColor: COLORS.infoBg,
  borderRadius: RADIUS.md,
  padding: '12px 16px',
  margin: '20px 0 4px',
}

const supportText: React.CSSProperties = {
  fontSize: '13px',
  color: COLORS.infoFg,
  margin: 0,
  lineHeight: 1.5,
}

const inlineLink: React.CSSProperties = {
  color: COLORS.green,
  fontWeight: 600,
  textDecoration: 'underline',
}

const h1: React.CSSProperties = {
  fontSize: '22px',
  fontWeight: 700,
  color: COLORS.text,
  margin: '0 0 12px',
  lineHeight: 1.3,
  fontFamily: FONT_STACK,
}

const h2: React.CSSProperties = {
  fontSize: '16px',
  fontWeight: 600,
  color: COLORS.text,
  margin: '20px 0 8px',
  fontFamily: FONT_STACK,
}

const p: React.CSSProperties = {
  fontSize: '15px',
  color: COLORS.text,
  lineHeight: 1.55,
  margin: '0 0 14px',
}

const pMuted: React.CSSProperties = {
  fontSize: '13px',
  color: COLORS.textMuted,
  lineHeight: 1.55,
  margin: '14px 0 0',
}

const hr: React.CSSProperties = {
  border: 'none',
  borderTop: `1px solid ${COLORS.border}`,
  margin: '20px 0',
}

const amountLabel: React.CSSProperties = {
  fontSize: '12px',
  color: COLORS.textMuted,
  margin: '0 0 4px',
  textTransform: 'uppercase',
  letterSpacing: '0.06em',
}

const amountValue: React.CSSProperties = {
  fontSize: '28px',
  fontWeight: 700,
  margin: 0,
  fontFamily: FONT_STACK,
}