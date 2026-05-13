// CHOP CHOP — AI provider abstraction.
// All AI calls go through this layer so we can swap Lovable AI Gateway for
// OpenAI direct, Azure OpenAI, or another provider without touching callers.

export interface ChatMessage {
  role: 'system' | 'user' | 'assistant'
  content: string
}

export interface AIRequest {
  model: string
  messages: ChatMessage[]
  /** Optional JSON schema — when set, the provider must coerce output to JSON. */
  jsonSchema?: Record<string, unknown>
  temperature?: number
}

export interface AIResponse {
  text: string
  json?: unknown
  tokensInput?: number
  tokensOutput?: number
  raw?: unknown
}

export interface AIProvider {
  name: string
  chat(req: AIRequest): Promise<AIResponse>
}

// ---------- Lovable AI Gateway provider ----------

const LOVABLE_GATEWAY = 'https://ai.gateway.lovable.dev/v1/chat/completions'

export const lovableGateway: AIProvider = {
  name: 'lovable',
  async chat(req) {
    const apiKey = Deno.env.get('LOVABLE_API_KEY')
    if (!apiKey) throw new Error('LOVABLE_API_KEY not configured')

    const body: Record<string, unknown> = {
      model: req.model,
      messages: req.messages,
      temperature: req.temperature ?? 0.4,
    }

    if (req.jsonSchema) {
      body.tools = [
        {
          type: 'function',
          function: {
            name: 'respond',
            description: 'Return the structured response',
            parameters: req.jsonSchema,
          },
        },
      ]
      body.tool_choice = { type: 'function', function: { name: 'respond' } }
    }

    const resp = await fetch(LOVABLE_GATEWAY, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    })

    if (!resp.ok) {
      const errText = await resp.text().catch(() => '')
      const status = resp.status
      const code =
        status === 429 ? 'rate_limited' : status === 402 ? 'payment_required' : 'gateway_error'
      throw Object.assign(new Error(`Lovable AI ${status}: ${errText}`), {
        code,
        status,
      })
    }

    const data = await resp.json()
    const choice = data.choices?.[0]
    let text = choice?.message?.content ?? ''
    let json: unknown

    const toolCall = choice?.message?.tool_calls?.[0]
    if (toolCall?.function?.arguments) {
      try {
        json = JSON.parse(toolCall.function.arguments)
        text = JSON.stringify(json)
      } catch {
        // fall through with raw text
      }
    }

    return {
      text,
      json,
      tokensInput: data.usage?.prompt_tokens,
      tokensOutput: data.usage?.completion_tokens,
      raw: data,
    }
  },
}

// ---------- Provider selection ----------

export function getProvider(name?: string): AIProvider {
  switch ((name ?? Deno.env.get('AI_PROVIDER') ?? 'lovable').toLowerCase()) {
    case 'lovable':
      return lovableGateway
    // To add OpenAI / Azure later:
    // case 'openai': return openAIDirect
    // case 'azure':  return azureOpenAI
    default:
      return lovableGateway
  }
}