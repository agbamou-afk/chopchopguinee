export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  public: {
    Tables: {
      admin_users: {
        Row: {
          admin_role: Database["public"]["Enums"]["admin_role"]
          created_at: string
          created_by: string | null
          id: string
          notes: string | null
          status: Database["public"]["Enums"]["admin_user_status"]
          updated_at: string
          user_id: string
        }
        Insert: {
          admin_role: Database["public"]["Enums"]["admin_role"]
          created_at?: string
          created_by?: string | null
          id?: string
          notes?: string | null
          status?: Database["public"]["Enums"]["admin_user_status"]
          updated_at?: string
          user_id: string
        }
        Update: {
          admin_role?: Database["public"]["Enums"]["admin_role"]
          created_at?: string
          created_by?: string | null
          id?: string
          notes?: string | null
          status?: Database["public"]["Enums"]["admin_user_status"]
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      agent_profiles: {
        Row: {
          business_name: string
          commission_rate: number
          created_at: string
          daily_limit_gnf: number
          id: string
          latitude: number | null
          location: string | null
          longitude: number | null
          prepaid_float_gnf: number
          status: Database["public"]["Enums"]["wallet_status"]
          updated_at: string
          user_id: string
        }
        Insert: {
          business_name: string
          commission_rate?: number
          created_at?: string
          daily_limit_gnf?: number
          id?: string
          latitude?: number | null
          location?: string | null
          longitude?: number | null
          prepaid_float_gnf?: number
          status?: Database["public"]["Enums"]["wallet_status"]
          updated_at?: string
          user_id: string
        }
        Update: {
          business_name?: string
          commission_rate?: number
          created_at?: string
          daily_limit_gnf?: number
          id?: string
          latitude?: number | null
          location?: string | null
          longitude?: number | null
          prepaid_float_gnf?: number
          status?: Database["public"]["Enums"]["wallet_status"]
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      ai_insights: {
        Row: {
          confidence: Database["public"]["Enums"]["insight_confidence"]
          created_at: string
          generated_by_user_id: string | null
          generated_for_date: string
          id: string
          metrics: Json
          recommendation: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          section: Database["public"]["Enums"]["insight_section"]
          status: string
          summary: string
          title: string
        }
        Insert: {
          confidence?: Database["public"]["Enums"]["insight_confidence"]
          created_at?: string
          generated_by_user_id?: string | null
          generated_for_date?: string
          id?: string
          metrics?: Json
          recommendation?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          section: Database["public"]["Enums"]["insight_section"]
          status?: string
          summary: string
          title: string
        }
        Update: {
          confidence?: Database["public"]["Enums"]["insight_confidence"]
          created_at?: string
          generated_by_user_id?: string | null
          generated_for_date?: string
          id?: string
          metrics?: Json
          recommendation?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          section?: Database["public"]["Enums"]["insight_section"]
          status?: string
          summary?: string
          title?: string
        }
        Relationships: []
      }
      ai_rate_limits: {
        Row: {
          count: number
          user_id: string
          window_kind: string
          window_start: string
        }
        Insert: {
          count?: number
          user_id: string
          window_kind: string
          window_start: string
        }
        Update: {
          count?: number
          user_id?: string
          window_kind?: string
          window_start?: string
        }
        Relationships: []
      }
      ai_request_log: {
        Row: {
          action: string
          assistant: Database["public"]["Enums"]["ai_assistant_kind"]
          created_at: string
          error_message: string | null
          id: string
          input: Json
          latency_ms: number | null
          model: string
          output: Json | null
          prompt_summary: string | null
          provider: string
          status: Database["public"]["Enums"]["ai_request_status"]
          tokens_input: number | null
          tokens_output: number | null
          user_id: string | null
        }
        Insert: {
          action: string
          assistant: Database["public"]["Enums"]["ai_assistant_kind"]
          created_at?: string
          error_message?: string | null
          id?: string
          input?: Json
          latency_ms?: number | null
          model: string
          output?: Json | null
          prompt_summary?: string | null
          provider: string
          status?: Database["public"]["Enums"]["ai_request_status"]
          tokens_input?: number | null
          tokens_output?: number | null
          user_id?: string | null
        }
        Update: {
          action?: string
          assistant?: Database["public"]["Enums"]["ai_assistant_kind"]
          created_at?: string
          error_message?: string | null
          id?: string
          input?: Json
          latency_ms?: number | null
          model?: string
          output?: Json | null
          prompt_summary?: string | null
          provider?: string
          status?: Database["public"]["Enums"]["ai_request_status"]
          tokens_input?: number | null
          tokens_output?: number | null
          user_id?: string | null
        }
        Relationships: []
      }
      analytics_events: {
        Row: {
          anonymous_session_id: string | null
          app_version: string | null
          created_at: string
          device_type: string | null
          event_category: string
          event_name: string
          event_type: string
          id: string
          language: string | null
          metadata: Json
          os: string | null
          route: string | null
          service_area: string | null
          user_id: string | null
          zone_city: string | null
          zone_commune: string | null
          zone_country: string | null
          zone_neighborhood: string | null
        }
        Insert: {
          anonymous_session_id?: string | null
          app_version?: string | null
          created_at?: string
          device_type?: string | null
          event_category: string
          event_name: string
          event_type: string
          id?: string
          language?: string | null
          metadata?: Json
          os?: string | null
          route?: string | null
          service_area?: string | null
          user_id?: string | null
          zone_city?: string | null
          zone_commune?: string | null
          zone_country?: string | null
          zone_neighborhood?: string | null
        }
        Update: {
          anonymous_session_id?: string | null
          app_version?: string | null
          created_at?: string
          device_type?: string | null
          event_category?: string
          event_name?: string
          event_type?: string
          id?: string
          language?: string | null
          metadata?: Json
          os?: string | null
          route?: string | null
          service_area?: string | null
          user_id?: string | null
          zone_city?: string | null
          zone_commune?: string | null
          zone_country?: string | null
          zone_neighborhood?: string | null
        }
        Relationships: []
      }
      app_settings: {
        Row: {
          description: string | null
          key: string
          updated_at: string
          updated_by: string | null
          value: Json
        }
        Insert: {
          description?: string | null
          key: string
          updated_at?: string
          updated_by?: string | null
          value?: Json
        }
        Update: {
          description?: string | null
          key?: string
          updated_at?: string
          updated_by?: string | null
          value?: Json
        }
        Relationships: []
      }
      approval_requests: {
        Row: {
          action: string
          created_at: string
          id: string
          module: string
          payload: Json
          requested_by: string
          requested_role: Database["public"]["Enums"]["admin_role"] | null
          review_note: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          status: Database["public"]["Enums"]["approval_status"]
        }
        Insert: {
          action: string
          created_at?: string
          id?: string
          module: string
          payload?: Json
          requested_by: string
          requested_role?: Database["public"]["Enums"]["admin_role"] | null
          review_note?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: Database["public"]["Enums"]["approval_status"]
        }
        Update: {
          action?: string
          created_at?: string
          id?: string
          module?: string
          payload?: Json
          requested_by?: string
          requested_role?: Database["public"]["Enums"]["admin_role"] | null
          review_note?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: Database["public"]["Enums"]["approval_status"]
        }
        Relationships: []
      }
      audit_logs: {
        Row: {
          action: string
          actor_role: Database["public"]["Enums"]["admin_role"] | null
          actor_user_id: string | null
          after: Json | null
          before: Json | null
          created_at: string
          id: string
          ip: string | null
          module: string
          note: string | null
          target_id: string | null
          target_type: string | null
          user_agent: string | null
        }
        Insert: {
          action: string
          actor_role?: Database["public"]["Enums"]["admin_role"] | null
          actor_user_id?: string | null
          after?: Json | null
          before?: Json | null
          created_at?: string
          id?: string
          ip?: string | null
          module: string
          note?: string | null
          target_id?: string | null
          target_type?: string | null
          user_agent?: string | null
        }
        Update: {
          action?: string
          actor_role?: Database["public"]["Enums"]["admin_role"] | null
          actor_user_id?: string | null
          after?: Json | null
          before?: Json | null
          created_at?: string
          id?: string
          ip?: string | null
          module?: string
          note?: string | null
          target_id?: string | null
          target_type?: string | null
          user_agent?: string | null
        }
        Relationships: []
      }
      conversations: {
        Row: {
          buyer_id: string
          created_at: string
          id: string
          last_message_at: string
          listing_id: string
          seller_id: string
        }
        Insert: {
          buyer_id: string
          created_at?: string
          id?: string
          last_message_at?: string
          listing_id: string
          seller_id: string
        }
        Update: {
          buyer_id?: string
          created_at?: string
          id?: string
          last_message_at?: string
          listing_id?: string
          seller_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "conversations_listing_id_fkey"
            columns: ["listing_id"]
            isOneToOne: false
            referencedRelation: "marketplace_listings"
            referencedColumns: ["id"]
          },
        ]
      }
      driver_applications: {
        Row: {
          created_at: string
          decided_at: string | null
          decided_by: string | null
          decision: Database["public"]["Enums"]["driver_application_decision"]
          decision_reason: string | null
          id: string
          payload: Json
          user_id: string
        }
        Insert: {
          created_at?: string
          decided_at?: string | null
          decided_by?: string | null
          decision?: Database["public"]["Enums"]["driver_application_decision"]
          decision_reason?: string | null
          id?: string
          payload?: Json
          user_id: string
        }
        Update: {
          created_at?: string
          decided_at?: string | null
          decided_by?: string | null
          decision?: Database["public"]["Enums"]["driver_application_decision"]
          decision_reason?: string | null
          id?: string
          payload?: Json
          user_id?: string
        }
        Relationships: []
      }
      driver_cash_ledger: {
        Row: {
          cash_collected_gnf: number
          commission_owed_gnf: number
          created_at: string
          driver_id: string
          id: string
          note: string | null
          ride_id: string | null
          settled_amount_gnf: number
          settled_at: string | null
        }
        Insert: {
          cash_collected_gnf?: number
          commission_owed_gnf?: number
          created_at?: string
          driver_id: string
          id?: string
          note?: string | null
          ride_id?: string | null
          settled_amount_gnf?: number
          settled_at?: string | null
        }
        Update: {
          cash_collected_gnf?: number
          commission_owed_gnf?: number
          created_at?: string
          driver_id?: string
          id?: string
          note?: string | null
          ride_id?: string | null
          settled_amount_gnf?: number
          settled_at?: string | null
        }
        Relationships: []
      }
      driver_locations: {
        Row: {
          heading: number | null
          lat: number
          lng: number
          speed: number | null
          status: string
          updated_at: string
          user_id: string
          zone: string | null
        }
        Insert: {
          heading?: number | null
          lat: number
          lng: number
          speed?: number | null
          status?: string
          updated_at?: string
          user_id: string
          zone?: string | null
        }
        Update: {
          heading?: number | null
          lat?: number
          lng?: number
          speed?: number | null
          status?: string
          updated_at?: string
          user_id?: string
          zone?: string | null
        }
        Relationships: []
      }
      driver_profiles: {
        Row: {
          accept_rate: number
          approved_at: string | null
          approved_by: string | null
          cash_debt_gnf: number
          created_at: string
          debt_limit_gnf: number
          driver_photo_url: string | null
          id_doc_url: string | null
          last_seen_at: string | null
          plate_number: string | null
          presence: Database["public"]["Enums"]["driver_presence"]
          rating: number
          rejected_reason: string | null
          status: Database["public"]["Enums"]["driver_status"]
          suspended_reason: string | null
          updated_at: string
          user_id: string
          vehicle_photo_url: string | null
          vehicle_type: Database["public"]["Enums"]["driver_vehicle_type"]
          zones: string[]
        }
        Insert: {
          accept_rate?: number
          approved_at?: string | null
          approved_by?: string | null
          cash_debt_gnf?: number
          created_at?: string
          debt_limit_gnf?: number
          driver_photo_url?: string | null
          id_doc_url?: string | null
          last_seen_at?: string | null
          plate_number?: string | null
          presence?: Database["public"]["Enums"]["driver_presence"]
          rating?: number
          rejected_reason?: string | null
          status?: Database["public"]["Enums"]["driver_status"]
          suspended_reason?: string | null
          updated_at?: string
          user_id: string
          vehicle_photo_url?: string | null
          vehicle_type?: Database["public"]["Enums"]["driver_vehicle_type"]
          zones?: string[]
        }
        Update: {
          accept_rate?: number
          approved_at?: string | null
          approved_by?: string | null
          cash_debt_gnf?: number
          created_at?: string
          debt_limit_gnf?: number
          driver_photo_url?: string | null
          id_doc_url?: string | null
          last_seen_at?: string | null
          plate_number?: string | null
          presence?: Database["public"]["Enums"]["driver_presence"]
          rating?: number
          rejected_reason?: string | null
          status?: Database["public"]["Enums"]["driver_status"]
          suspended_reason?: string | null
          updated_at?: string
          user_id?: string
          vehicle_photo_url?: string | null
          vehicle_type?: Database["public"]["Enums"]["driver_vehicle_type"]
          zones?: string[]
        }
        Relationships: []
      }
      email_send_log: {
        Row: {
          created_at: string
          error_message: string | null
          id: string
          message_id: string | null
          metadata: Json | null
          recipient_email: string
          status: string
          template_name: string
        }
        Insert: {
          created_at?: string
          error_message?: string | null
          id?: string
          message_id?: string | null
          metadata?: Json | null
          recipient_email: string
          status: string
          template_name: string
        }
        Update: {
          created_at?: string
          error_message?: string | null
          id?: string
          message_id?: string | null
          metadata?: Json | null
          recipient_email?: string
          status?: string
          template_name?: string
        }
        Relationships: []
      }
      email_send_state: {
        Row: {
          auth_email_ttl_minutes: number
          batch_size: number
          id: number
          retry_after_until: string | null
          send_delay_ms: number
          transactional_email_ttl_minutes: number
          updated_at: string
        }
        Insert: {
          auth_email_ttl_minutes?: number
          batch_size?: number
          id?: number
          retry_after_until?: string | null
          send_delay_ms?: number
          transactional_email_ttl_minutes?: number
          updated_at?: string
        }
        Update: {
          auth_email_ttl_minutes?: number
          batch_size?: number
          id?: number
          retry_after_until?: string | null
          send_delay_ms?: number
          transactional_email_ttl_minutes?: number
          updated_at?: string
        }
        Relationships: []
      }
      email_unsubscribe_tokens: {
        Row: {
          created_at: string
          email: string
          id: string
          token: string
          used_at: string | null
        }
        Insert: {
          created_at?: string
          email: string
          id?: string
          token: string
          used_at?: string | null
        }
        Update: {
          created_at?: string
          email?: string
          id?: string
          token?: string
          used_at?: string | null
        }
        Relationships: []
      }
      fare_settings: {
        Row: {
          base_price: number
          currency: string
          id: string
          price_per_km: number
          ride_type: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          base_price?: number
          currency?: string
          id?: string
          price_per_km?: number
          ride_type: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          base_price?: number
          currency?: string
          id?: string
          price_per_km?: number
          ride_type?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: []
      }
      feature_flags: {
        Row: {
          description: string | null
          enabled: boolean
          key: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          description?: string | null
          enabled?: boolean
          key: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          description?: string | null
          enabled?: boolean
          key?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: []
      }
      landmarks: {
        Row: {
          active: boolean
          aliases: string[]
          category: string
          commune: string | null
          created_at: string
          id: string
          lat: number
          lng: number
          name: string
          neighborhood: string | null
          popularity: number
          updated_at: string
        }
        Insert: {
          active?: boolean
          aliases?: string[]
          category: string
          commune?: string | null
          created_at?: string
          id?: string
          lat: number
          lng: number
          name: string
          neighborhood?: string | null
          popularity?: number
          updated_at?: string
        }
        Update: {
          active?: boolean
          aliases?: string[]
          category?: string
          commune?: string | null
          created_at?: string
          id?: string
          lat?: number
          lng?: number
          name?: string
          neighborhood?: string | null
          popularity?: number
          updated_at?: string
        }
        Relationships: []
      }
      listing_images: {
        Row: {
          created_at: string
          id: string
          listing_id: string
          position: number
          url: string
        }
        Insert: {
          created_at?: string
          id?: string
          listing_id: string
          position?: number
          url: string
        }
        Update: {
          created_at?: string
          id?: string
          listing_id?: string
          position?: number
          url?: string
        }
        Relationships: [
          {
            foreignKeyName: "listing_images_listing_id_fkey"
            columns: ["listing_id"]
            isOneToOne: false
            referencedRelation: "marketplace_listings"
            referencedColumns: ["id"]
          },
        ]
      }
      listing_reports: {
        Row: {
          created_at: string
          details: string | null
          id: string
          listing_id: string
          reason: string
          reporter_id: string | null
          status: Database["public"]["Enums"]["report_status"]
        }
        Insert: {
          created_at?: string
          details?: string | null
          id?: string
          listing_id: string
          reason: string
          reporter_id?: string | null
          status?: Database["public"]["Enums"]["report_status"]
        }
        Update: {
          created_at?: string
          details?: string | null
          id?: string
          listing_id?: string
          reason?: string
          reporter_id?: string | null
          status?: Database["public"]["Enums"]["report_status"]
        }
        Relationships: [
          {
            foreignKeyName: "listing_reports_listing_id_fkey"
            columns: ["listing_id"]
            isOneToOne: false
            referencedRelation: "marketplace_listings"
            referencedColumns: ["id"]
          },
        ]
      }
      map_provider_settings: {
        Row: {
          default_lat: number
          default_lng: number
          default_zoom: number
          flags: Json
          id: number
          routing_provider: string
          style_url: string
          updated_at: string
        }
        Insert: {
          default_lat?: number
          default_lng?: number
          default_zoom?: number
          flags?: Json
          id?: number
          routing_provider?: string
          style_url?: string
          updated_at?: string
        }
        Update: {
          default_lat?: number
          default_lng?: number
          default_zoom?: number
          flags?: Json
          id?: number
          routing_provider?: string
          style_url?: string
          updated_at?: string
        }
        Relationships: []
      }
      maps_rate_limits: {
        Row: {
          count: number
          user_id: string
          window_kind: string
          window_start: string
        }
        Insert: {
          count?: number
          user_id: string
          window_kind: string
          window_start: string
        }
        Update: {
          count?: number
          user_id?: string
          window_kind?: string
          window_start?: string
        }
        Relationships: []
      }
      maps_request_log: {
        Row: {
          action: string
          created_at: string
          error_message: string | null
          id: string
          input: Json
          latency_ms: number | null
          output_summary: Json | null
          provider: string
          status: string
          user_id: string | null
        }
        Insert: {
          action: string
          created_at?: string
          error_message?: string | null
          id?: string
          input?: Json
          latency_ms?: number | null
          output_summary?: Json | null
          provider: string
          status?: string
          user_id?: string | null
        }
        Update: {
          action?: string
          created_at?: string
          error_message?: string | null
          id?: string
          input?: Json
          latency_ms?: number | null
          output_summary?: Json | null
          provider?: string
          status?: string
          user_id?: string | null
        }
        Relationships: []
      }
      marketplace_listings: {
        Row: {
          category: string
          commune: string | null
          condition: string | null
          created_at: string
          delivery_available: boolean
          description: string | null
          id: string
          is_negotiable: boolean
          is_urgent: boolean
          kind: Database["public"]["Enums"]["listing_kind"]
          landmark: string | null
          neighborhood: string | null
          price_gnf: number | null
          seller_id: string
          status: Database["public"]["Enums"]["listing_status"]
          title: string
          updated_at: string
          view_count: number
        }
        Insert: {
          category: string
          commune?: string | null
          condition?: string | null
          created_at?: string
          delivery_available?: boolean
          description?: string | null
          id?: string
          is_negotiable?: boolean
          is_urgent?: boolean
          kind?: Database["public"]["Enums"]["listing_kind"]
          landmark?: string | null
          neighborhood?: string | null
          price_gnf?: number | null
          seller_id: string
          status?: Database["public"]["Enums"]["listing_status"]
          title: string
          updated_at?: string
          view_count?: number
        }
        Update: {
          category?: string
          commune?: string | null
          condition?: string | null
          created_at?: string
          delivery_available?: boolean
          description?: string | null
          id?: string
          is_negotiable?: boolean
          is_urgent?: boolean
          kind?: Database["public"]["Enums"]["listing_kind"]
          landmark?: string | null
          neighborhood?: string | null
          price_gnf?: number | null
          seller_id?: string
          status?: Database["public"]["Enums"]["listing_status"]
          title?: string
          updated_at?: string
          view_count?: number
        }
        Relationships: []
      }
      message_log: {
        Row: {
          body: string
          channel: Database["public"]["Enums"]["message_channel"]
          created_at: string
          delivered_at: string | null
          error: string | null
          id: string
          payload: Json
          provider: string
          provider_message_id: string | null
          retry_count: number
          sent_at: string | null
          status: Database["public"]["Enums"]["message_status"]
          template: Database["public"]["Enums"]["message_template"]
          to_address: string
          user_id: string | null
        }
        Insert: {
          body: string
          channel: Database["public"]["Enums"]["message_channel"]
          created_at?: string
          delivered_at?: string | null
          error?: string | null
          id?: string
          payload?: Json
          provider: string
          provider_message_id?: string | null
          retry_count?: number
          sent_at?: string | null
          status?: Database["public"]["Enums"]["message_status"]
          template: Database["public"]["Enums"]["message_template"]
          to_address: string
          user_id?: string | null
        }
        Update: {
          body?: string
          channel?: Database["public"]["Enums"]["message_channel"]
          created_at?: string
          delivered_at?: string | null
          error?: string | null
          id?: string
          payload?: Json
          provider?: string
          provider_message_id?: string | null
          retry_count?: number
          sent_at?: string | null
          status?: Database["public"]["Enums"]["message_status"]
          template?: Database["public"]["Enums"]["message_template"]
          to_address?: string
          user_id?: string | null
        }
        Relationships: []
      }
      messages: {
        Row: {
          attachment_url: string | null
          body: string | null
          conversation_id: string
          created_at: string
          id: string
          kind: Database["public"]["Enums"]["message_kind"]
          sender_id: string
        }
        Insert: {
          attachment_url?: string | null
          body?: string | null
          conversation_id: string
          created_at?: string
          id?: string
          kind?: Database["public"]["Enums"]["message_kind"]
          sender_id: string
        }
        Update: {
          attachment_url?: string | null
          body?: string | null
          conversation_id?: string
          created_at?: string
          id?: string
          kind?: Database["public"]["Enums"]["message_kind"]
          sender_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "messages_conversation_id_fkey"
            columns: ["conversation_id"]
            isOneToOne: false
            referencedRelation: "conversations"
            referencedColumns: ["id"]
          },
        ]
      }
      notification_log: {
        Row: {
          channel: Database["public"]["Enums"]["notification_channel"]
          created_at: string
          error_message: string | null
          external_id: string | null
          id: string
          payload: Json
          priority: Database["public"]["Enums"]["notification_priority"]
          recipient: string | null
          status: Database["public"]["Enums"]["notification_status"]
          template: string
          updated_at: string
          user_id: string | null
        }
        Insert: {
          channel: Database["public"]["Enums"]["notification_channel"]
          created_at?: string
          error_message?: string | null
          external_id?: string | null
          id?: string
          payload?: Json
          priority?: Database["public"]["Enums"]["notification_priority"]
          recipient?: string | null
          status?: Database["public"]["Enums"]["notification_status"]
          template: string
          updated_at?: string
          user_id?: string | null
        }
        Update: {
          channel?: Database["public"]["Enums"]["notification_channel"]
          created_at?: string
          error_message?: string | null
          external_id?: string | null
          id?: string
          payload?: Json
          priority?: Database["public"]["Enums"]["notification_priority"]
          recipient?: string | null
          status?: Database["public"]["Enums"]["notification_status"]
          template?: string
          updated_at?: string
          user_id?: string | null
        }
        Relationships: []
      }
      notification_preferences: {
        Row: {
          created_at: string
          preferred_channel: Database["public"]["Enums"]["message_channel"]
          sms_enabled: boolean
          topic_marketing: boolean
          topic_otp: boolean
          topic_ride: boolean
          topic_wallet: boolean
          updated_at: string
          user_id: string
          whatsapp_enabled: boolean
        }
        Insert: {
          created_at?: string
          preferred_channel?: Database["public"]["Enums"]["message_channel"]
          sms_enabled?: boolean
          topic_marketing?: boolean
          topic_otp?: boolean
          topic_ride?: boolean
          topic_wallet?: boolean
          updated_at?: string
          user_id: string
          whatsapp_enabled?: boolean
        }
        Update: {
          created_at?: string
          preferred_channel?: Database["public"]["Enums"]["message_channel"]
          sms_enabled?: boolean
          topic_marketing?: boolean
          topic_otp?: boolean
          topic_ride?: boolean
          topic_wallet?: boolean
          updated_at?: string
          user_id?: string
          whatsapp_enabled?: boolean
        }
        Relationships: []
      }
      payment_provider_events: {
        Row: {
          amount_gnf: number
          created_at: string
          currency: string
          event_type: string
          id: string
          match_confidence: number | null
          matched_topup_request_id: string | null
          matched_user_id: string | null
          notes: string | null
          payer_phone: string | null
          processed_at: string | null
          processing_status: string
          provider: string
          provider_transaction_id: string
          raw_payload: Json
          status: string
        }
        Insert: {
          amount_gnf: number
          created_at?: string
          currency?: string
          event_type?: string
          id?: string
          match_confidence?: number | null
          matched_topup_request_id?: string | null
          matched_user_id?: string | null
          notes?: string | null
          payer_phone?: string | null
          processed_at?: string | null
          processing_status?: string
          provider: string
          provider_transaction_id: string
          raw_payload?: Json
          status?: string
        }
        Update: {
          amount_gnf?: number
          created_at?: string
          currency?: string
          event_type?: string
          id?: string
          match_confidence?: number | null
          matched_topup_request_id?: string | null
          matched_user_id?: string | null
          notes?: string | null
          payer_phone?: string | null
          processed_at?: string | null
          processing_status?: string
          provider?: string
          provider_transaction_id?: string
          raw_payload?: Json
          status?: string
        }
        Relationships: []
      }
      profiles: {
        Row: {
          account_status: string
          avatar_url: string | null
          created_at: string
          display_name: string | null
          email: string | null
          first_name: string | null
          full_name: string | null
          has_pin: boolean
          id: string
          kyc_level: number
          language: string
          last_name: string | null
          phone: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          account_status?: string
          avatar_url?: string | null
          created_at?: string
          display_name?: string | null
          email?: string | null
          first_name?: string | null
          full_name?: string | null
          has_pin?: boolean
          id?: string
          kyc_level?: number
          language?: string
          last_name?: string | null
          phone?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          account_status?: string
          avatar_url?: string | null
          created_at?: string
          display_name?: string | null
          email?: string | null
          first_name?: string | null
          full_name?: string | null
          has_pin?: boolean
          id?: string
          kyc_level?: number
          language?: string
          last_name?: string | null
          phone?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      ride_offers: {
        Row: {
          decline_reason: string | null
          destination_zone: string | null
          distance_to_pickup_m: number | null
          driver_id: string
          estimated_earning_gnf: number | null
          estimated_fare_gnf: number | null
          expires_at: string
          id: string
          pickup_zone: string | null
          responded_at: string | null
          ride_id: string
          sent_at: string
          status: Database["public"]["Enums"]["ride_offer_status"]
        }
        Insert: {
          decline_reason?: string | null
          destination_zone?: string | null
          distance_to_pickup_m?: number | null
          driver_id: string
          estimated_earning_gnf?: number | null
          estimated_fare_gnf?: number | null
          expires_at?: string
          id?: string
          pickup_zone?: string | null
          responded_at?: string | null
          ride_id: string
          sent_at?: string
          status?: Database["public"]["Enums"]["ride_offer_status"]
        }
        Update: {
          decline_reason?: string | null
          destination_zone?: string | null
          distance_to_pickup_m?: number | null
          driver_id?: string
          estimated_earning_gnf?: number | null
          estimated_fare_gnf?: number | null
          expires_at?: string
          id?: string
          pickup_zone?: string | null
          responded_at?: string | null
          ride_id?: string
          sent_at?: string
          status?: Database["public"]["Enums"]["ride_offer_status"]
        }
        Relationships: []
      }
      ride_ratings: {
        Row: {
          comment: string | null
          created_at: string
          direction: Database["public"]["Enums"]["rating_direction"]
          id: string
          ratee_id: string
          rater_id: string
          ride_id: string
          score: number
        }
        Insert: {
          comment?: string | null
          created_at?: string
          direction: Database["public"]["Enums"]["rating_direction"]
          id?: string
          ratee_id: string
          rater_id: string
          ride_id: string
          score: number
        }
        Update: {
          comment?: string | null
          created_at?: string
          direction?: Database["public"]["Enums"]["rating_direction"]
          id?: string
          ratee_id?: string
          rater_id?: string
          ride_id?: string
          score?: number
        }
        Relationships: []
      }
      rides: {
        Row: {
          client_id: string
          completed_at: string | null
          created_at: string
          dest_lat: number | null
          dest_lng: number | null
          driver_earning_gnf: number
          driver_id: string | null
          fare_gnf: number
          hold_tx_id: string | null
          id: string
          metadata: Json | null
          mode: Database["public"]["Enums"]["ride_mode"]
          payment_tx_id: string | null
          pickup_lat: number
          pickup_lng: number
          platform_fee_gnf: number
          status: Database["public"]["Enums"]["ride_status"]
          updated_at: string
        }
        Insert: {
          client_id: string
          completed_at?: string | null
          created_at?: string
          dest_lat?: number | null
          dest_lng?: number | null
          driver_earning_gnf?: number
          driver_id?: string | null
          fare_gnf: number
          hold_tx_id?: string | null
          id?: string
          metadata?: Json | null
          mode: Database["public"]["Enums"]["ride_mode"]
          payment_tx_id?: string | null
          pickup_lat: number
          pickup_lng: number
          platform_fee_gnf?: number
          status?: Database["public"]["Enums"]["ride_status"]
          updated_at?: string
        }
        Update: {
          client_id?: string
          completed_at?: string | null
          created_at?: string
          dest_lat?: number | null
          dest_lng?: number | null
          driver_earning_gnf?: number
          driver_id?: string | null
          fare_gnf?: number
          hold_tx_id?: string | null
          id?: string
          metadata?: Json | null
          mode?: Database["public"]["Enums"]["ride_mode"]
          payment_tx_id?: string | null
          pickup_lat?: number
          pickup_lng?: number
          platform_fee_gnf?: number
          status?: Database["public"]["Enums"]["ride_status"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "rides_hold_tx_id_fkey"
            columns: ["hold_tx_id"]
            isOneToOne: false
            referencedRelation: "wallet_transactions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "rides_payment_tx_id_fkey"
            columns: ["payment_tx_id"]
            isOneToOne: false
            referencedRelation: "wallet_transactions"
            referencedColumns: ["id"]
          },
        ]
      }
      saved_listings: {
        Row: {
          created_at: string
          listing_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          listing_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          listing_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "saved_listings_listing_id_fkey"
            columns: ["listing_id"]
            isOneToOne: false
            referencedRelation: "marketplace_listings"
            referencedColumns: ["id"]
          },
        ]
      }
      saved_places: {
        Row: {
          created_at: string
          id: string
          kind: Database["public"]["Enums"]["saved_place_kind"]
          label: string
          landmark_note: string | null
          lat: number
          lng: number
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          kind?: Database["public"]["Enums"]["saved_place_kind"]
          label: string
          landmark_note?: string | null
          lat: number
          lng: number
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          kind?: Database["public"]["Enums"]["saved_place_kind"]
          label?: string
          landmark_note?: string | null
          lat?: number
          lng?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      service_profiles: {
        Row: {
          availability: string | null
          bio: string | null
          created_at: string
          id: string
          portfolio_urls: string[]
          pricing_range: string | null
          profession: string
          rating: number
          response_rate: number
          service_areas: string[]
          updated_at: string
          user_id: string
        }
        Insert: {
          availability?: string | null
          bio?: string | null
          created_at?: string
          id?: string
          portfolio_urls?: string[]
          pricing_range?: string | null
          profession: string
          rating?: number
          response_rate?: number
          service_areas?: string[]
          updated_at?: string
          user_id: string
        }
        Update: {
          availability?: string | null
          bio?: string | null
          created_at?: string
          id?: string
          portfolio_urls?: string[]
          pricing_range?: string | null
          profession?: string
          rating?: number
          response_rate?: number
          service_areas?: string[]
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      support_messages: {
        Row: {
          created_at: string
          id: string
          message: string
          status: string
          user_id: string | null
        }
        Insert: {
          created_at?: string
          id?: string
          message: string
          status?: string
          user_id?: string | null
        }
        Update: {
          created_at?: string
          id?: string
          message?: string
          status?: string
          user_id?: string | null
        }
        Relationships: []
      }
      suppressed_emails: {
        Row: {
          created_at: string
          email: string
          id: string
          metadata: Json | null
          reason: string
        }
        Insert: {
          created_at?: string
          email: string
          id?: string
          metadata?: Json | null
          reason: string
        }
        Update: {
          created_at?: string
          email?: string
          id?: string
          metadata?: Json | null
          reason?: string
        }
        Relationships: []
      }
      topup_requests: {
        Row: {
          agent_user_id: string | null
          amount_gnf: number
          cancelled_reason: string | null
          client_user_id: string
          confirmation_code: string
          confirmed_at: string | null
          created_at: string
          expires_at: string
          id: string
          matched_provider_transaction_id: string | null
          notes: string | null
          provider: string
          reference: string
          status: Database["public"]["Enums"]["topup_status"]
          transaction_id: string | null
          updated_at: string
          user_phone: string | null
        }
        Insert: {
          agent_user_id?: string | null
          amount_gnf: number
          cancelled_reason?: string | null
          client_user_id: string
          confirmation_code: string
          confirmed_at?: string | null
          created_at?: string
          expires_at?: string
          id?: string
          matched_provider_transaction_id?: string | null
          notes?: string | null
          provider?: string
          reference: string
          status?: Database["public"]["Enums"]["topup_status"]
          transaction_id?: string | null
          updated_at?: string
          user_phone?: string | null
        }
        Update: {
          agent_user_id?: string | null
          amount_gnf?: number
          cancelled_reason?: string | null
          client_user_id?: string
          confirmation_code?: string
          confirmed_at?: string | null
          created_at?: string
          expires_at?: string
          id?: string
          matched_provider_transaction_id?: string | null
          notes?: string | null
          provider?: string
          reference?: string
          status?: Database["public"]["Enums"]["topup_status"]
          transaction_id?: string | null
          updated_at?: string
          user_phone?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "topup_requests_transaction_id_fkey"
            columns: ["transaction_id"]
            isOneToOne: false
            referencedRelation: "wallet_transactions"
            referencedColumns: ["id"]
          },
        ]
      }
      user_consent: {
        Row: {
          basic_analytics: boolean
          consent_version: number
          created_at: string
          location_improvements: boolean
          marketing_analytics: boolean
          personalization: boolean
          security_fraud: boolean
          updated_at: string
          user_id: string
        }
        Insert: {
          basic_analytics?: boolean
          consent_version?: number
          created_at?: string
          location_improvements?: boolean
          marketing_analytics?: boolean
          personalization?: boolean
          security_fraud?: boolean
          updated_at?: string
          user_id: string
        }
        Update: {
          basic_analytics?: boolean
          consent_version?: number
          created_at?: string
          location_improvements?: boolean
          marketing_analytics?: boolean
          personalization?: boolean
          security_fraud?: boolean
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      user_pins: {
        Row: {
          pin_hash: string
          updated_at: string
          user_id: string
        }
        Insert: {
          pin_hash: string
          updated_at?: string
          user_id: string
        }
        Update: {
          pin_hash?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      user_roles: {
        Row: {
          created_at: string
          id: string
          role: Database["public"]["Enums"]["app_role"]
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          role: Database["public"]["Enums"]["app_role"]
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          role?: Database["public"]["Enums"]["app_role"]
          user_id?: string
        }
        Relationships: []
      }
      wallet_transactions: {
        Row: {
          amount_gnf: number
          completed_at: string | null
          created_at: string
          description: string | null
          from_wallet_id: string | null
          id: string
          metadata: Json
          reference: string
          related_entity: string | null
          related_user_id: string | null
          status: Database["public"]["Enums"]["txn_status"]
          to_wallet_id: string | null
          type: Database["public"]["Enums"]["txn_type"]
        }
        Insert: {
          amount_gnf: number
          completed_at?: string | null
          created_at?: string
          description?: string | null
          from_wallet_id?: string | null
          id?: string
          metadata?: Json
          reference: string
          related_entity?: string | null
          related_user_id?: string | null
          status?: Database["public"]["Enums"]["txn_status"]
          to_wallet_id?: string | null
          type: Database["public"]["Enums"]["txn_type"]
        }
        Update: {
          amount_gnf?: number
          completed_at?: string | null
          created_at?: string
          description?: string | null
          from_wallet_id?: string | null
          id?: string
          metadata?: Json
          reference?: string
          related_entity?: string | null
          related_user_id?: string | null
          status?: Database["public"]["Enums"]["txn_status"]
          to_wallet_id?: string | null
          type?: Database["public"]["Enums"]["txn_type"]
        }
        Relationships: [
          {
            foreignKeyName: "wallet_transactions_from_wallet_id_fkey"
            columns: ["from_wallet_id"]
            isOneToOne: false
            referencedRelation: "wallets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "wallet_transactions_to_wallet_id_fkey"
            columns: ["to_wallet_id"]
            isOneToOne: false
            referencedRelation: "wallets"
            referencedColumns: ["id"]
          },
        ]
      }
      wallets: {
        Row: {
          balance_gnf: number
          created_at: string
          currency: string
          held_gnf: number
          id: string
          owner_user_id: string | null
          party_type: Database["public"]["Enums"]["party_type"]
          status: Database["public"]["Enums"]["wallet_status"]
          updated_at: string
        }
        Insert: {
          balance_gnf?: number
          created_at?: string
          currency?: string
          held_gnf?: number
          id?: string
          owner_user_id?: string | null
          party_type: Database["public"]["Enums"]["party_type"]
          status?: Database["public"]["Enums"]["wallet_status"]
          updated_at?: string
        }
        Update: {
          balance_gnf?: number
          created_at?: string
          currency?: string
          held_gnf?: number
          id?: string
          owner_user_id?: string | null
          party_type?: Database["public"]["Enums"]["party_type"]
          status?: Database["public"]["Enums"]["wallet_status"]
          updated_at?: string
        }
        Relationships: []
      }
      zones: {
        Row: {
          city: string | null
          commune: string | null
          country: string
          created_at: string
          id: string
          kind: string
          metadata: Json
          neighborhood: string | null
          updated_at: string
        }
        Insert: {
          city?: string | null
          commune?: string | null
          country?: string
          created_at?: string
          id?: string
          kind?: string
          metadata?: Json
          neighborhood?: string | null
          updated_at?: string
        }
        Update: {
          city?: string | null
          commune?: string | null
          country?: string
          created_at?: string
          id?: string
          kind?: string
          metadata?: Json
          neighborhood?: string | null
          updated_at?: string
        }
        Relationships: []
      }
    }
    Views: {
      agent_topup_requests: {
        Row: {
          agent_user_id: string | null
          amount_gnf: number | null
          cancelled_reason: string | null
          client_user_id: string | null
          confirmed_at: string | null
          created_at: string | null
          expires_at: string | null
          id: string | null
          reference: string | null
          status: Database["public"]["Enums"]["topup_status"] | null
          transaction_id: string | null
          updated_at: string | null
        }
        Insert: {
          agent_user_id?: string | null
          amount_gnf?: number | null
          cancelled_reason?: string | null
          client_user_id?: string | null
          confirmed_at?: string | null
          created_at?: string | null
          expires_at?: string | null
          id?: string | null
          reference?: string | null
          status?: Database["public"]["Enums"]["topup_status"] | null
          transaction_id?: string | null
          updated_at?: string | null
        }
        Update: {
          agent_user_id?: string | null
          amount_gnf?: number | null
          cancelled_reason?: string | null
          client_user_id?: string | null
          confirmed_at?: string | null
          created_at?: string | null
          expires_at?: string | null
          id?: string | null
          reference?: string | null
          status?: Database["public"]["Enums"]["topup_status"] | null
          transaction_id?: string | null
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "topup_requests_transaction_id_fkey"
            columns: ["transaction_id"]
            isOneToOne: false
            referencedRelation: "wallet_transactions"
            referencedColumns: ["id"]
          },
        ]
      }
      public_agents: {
        Row: {
          business_name: string | null
          id: string | null
          latitude: number | null
          location: string | null
          longitude: number | null
          status: Database["public"]["Enums"]["wallet_status"] | null
          user_id: string | null
        }
        Insert: {
          business_name?: string | null
          id?: string | null
          latitude?: number | null
          location?: string | null
          longitude?: number | null
          status?: Database["public"]["Enums"]["wallet_status"] | null
          user_id?: string | null
        }
        Update: {
          business_name?: string | null
          id?: string | null
          latitude?: number | null
          location?: string | null
          longitude?: number | null
          status?: Database["public"]["Enums"]["wallet_status"] | null
          user_id?: string | null
        }
        Relationships: []
      }
    }
    Functions: {
      admin_adjust_agent_float: {
        Args: {
          p_agent_user_id: string
          p_delta_gnf: number
          p_reason?: string
        }
        Returns: {
          amount_gnf: number
          completed_at: string | null
          created_at: string
          description: string | null
          from_wallet_id: string | null
          id: string
          metadata: Json
          reference: string
          related_entity: string | null
          related_user_id: string | null
          status: Database["public"]["Enums"]["txn_status"]
          to_wallet_id: string | null
          type: Database["public"]["Enums"]["txn_type"]
        }
        SetofOptions: {
          from: "*"
          to: "wallet_transactions"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      admin_create_agent: {
        Args: {
          p_business_name: string
          p_commission_rate?: number
          p_daily_limit_gnf?: number
          p_location?: string
          p_phone: string
        }
        Returns: {
          business_name: string
          commission_rate: number
          created_at: string
          daily_limit_gnf: number
          id: string
          latitude: number | null
          location: string | null
          longitude: number | null
          prepaid_float_gnf: number
          status: Database["public"]["Enums"]["wallet_status"]
          updated_at: string
          user_id: string
        }
        SetofOptions: {
          from: "*"
          to: "agent_profiles"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      analytics_summary: { Args: { p_days?: number }; Returns: Json }
      can_access_admin: { Args: { _user_id: string }; Returns: boolean }
      can_manage_operations: { Args: { _user_id: string }; Returns: boolean }
      can_manage_wallet: { Args: { _user_id: string }; Returns: boolean }
      claim_first_admin: { Args: never; Returns: boolean }
      current_admin_role: {
        Args: { _user_id: string }
        Returns: Database["public"]["Enums"]["admin_role"]
      }
      delete_email: {
        Args: { message_id: number; queue_name: string }
        Returns: boolean
      }
      demo_reset_driver: { Args: never; Returns: Json }
      demo_seed_ride_offer: { Args: never; Returns: Json }
      driver_admin_decide: {
        Args: { p_decision: string; p_reason?: string; p_user_id: string }
        Returns: {
          accept_rate: number
          approved_at: string | null
          approved_by: string | null
          cash_debt_gnf: number
          created_at: string
          debt_limit_gnf: number
          driver_photo_url: string | null
          id_doc_url: string | null
          last_seen_at: string | null
          plate_number: string | null
          presence: Database["public"]["Enums"]["driver_presence"]
          rating: number
          rejected_reason: string | null
          status: Database["public"]["Enums"]["driver_status"]
          suspended_reason: string | null
          updated_at: string
          user_id: string
          vehicle_photo_url: string | null
          vehicle_type: Database["public"]["Enums"]["driver_vehicle_type"]
          zones: string[]
        }
        SetofOptions: {
          from: "*"
          to: "driver_profiles"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      driver_apply: {
        Args: { p_payload: Json }
        Returns: {
          created_at: string
          decided_at: string | null
          decided_by: string | null
          decision: Database["public"]["Enums"]["driver_application_decision"]
          decision_reason: string | null
          id: string
          payload: Json
          user_id: string
        }
        SetofOptions: {
          from: "*"
          to: "driver_applications"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      driver_cash_settle: {
        Args: {
          p_amount_gnf: number
          p_driver_user_id: string
          p_note?: string
        }
        Returns: {
          cash_collected_gnf: number
          commission_owed_gnf: number
          created_at: string
          driver_id: string
          id: string
          note: string | null
          ride_id: string | null
          settled_amount_gnf: number
          settled_at: string | null
        }
        SetofOptions: {
          from: "*"
          to: "driver_cash_ledger"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      driver_offer_accept: {
        Args: { p_offer_id: string }
        Returns: {
          decline_reason: string | null
          destination_zone: string | null
          distance_to_pickup_m: number | null
          driver_id: string
          estimated_earning_gnf: number | null
          estimated_fare_gnf: number | null
          expires_at: string
          id: string
          pickup_zone: string | null
          responded_at: string | null
          ride_id: string
          sent_at: string
          status: Database["public"]["Enums"]["ride_offer_status"]
        }
        SetofOptions: {
          from: "*"
          to: "ride_offers"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      driver_offer_decline: {
        Args: { p_offer_id: string; p_reason?: string }
        Returns: {
          decline_reason: string | null
          destination_zone: string | null
          distance_to_pickup_m: number | null
          driver_id: string
          estimated_earning_gnf: number | null
          estimated_fare_gnf: number | null
          expires_at: string
          id: string
          pickup_zone: string | null
          responded_at: string | null
          ride_id: string
          sent_at: string
          status: Database["public"]["Enums"]["ride_offer_status"]
        }
        SetofOptions: {
          from: "*"
          to: "ride_offers"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      driver_set_status: {
        Args: { p_status: Database["public"]["Enums"]["driver_presence"] }
        Returns: {
          accept_rate: number
          approved_at: string | null
          approved_by: string | null
          cash_debt_gnf: number
          created_at: string
          debt_limit_gnf: number
          driver_photo_url: string | null
          id_doc_url: string | null
          last_seen_at: string | null
          plate_number: string | null
          presence: Database["public"]["Enums"]["driver_presence"]
          rating: number
          rejected_reason: string | null
          status: Database["public"]["Enums"]["driver_status"]
          suspended_reason: string | null
          updated_at: string
          user_id: string
          vehicle_photo_url: string | null
          vehicle_type: Database["public"]["Enums"]["driver_vehicle_type"]
          zones: string[]
        }
        SetofOptions: {
          from: "*"
          to: "driver_profiles"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      enqueue_email: {
        Args: { payload: Json; queue_name: string }
        Returns: number
      }
      find_user_by_phone: {
        Args: { p_phone: string }
        Returns: {
          full_name: string
          user_id: string
        }[]
      }
      gen_topup_reference: { Args: never; Returns: string }
      has_admin_role: {
        Args: {
          _role: Database["public"]["Enums"]["admin_role"]
          _user_id: string
        }
        Returns: boolean
      }
      has_app_role: {
        Args: { _role: string; _user_id: string }
        Returns: boolean
      }
      has_role: {
        Args: {
          _role: Database["public"]["Enums"]["app_role"]
          _user_id: string
        }
        Returns: boolean
      }
      is_admin: { Args: { _user_id: string }; Returns: boolean }
      is_any_admin: { Args: { _user_id: string }; Returns: boolean }
      is_god_admin: { Args: { _user_id: string }; Returns: boolean }
      log_admin_action: {
        Args: {
          _action: string
          _after?: Json
          _before?: Json
          _module: string
          _note?: string
          _target_id?: string
          _target_type?: string
        }
        Returns: string
      }
      move_to_dlq: {
        Args: {
          dlq_name: string
          message_id: number
          payload: Json
          source_queue: string
        }
        Returns: number
      }
      om_auto_match: { Args: { p_event_id: string }; Returns: Json }
      om_pending_topups_for_event: {
        Args: { p_event_id: string }
        Returns: {
          amount_gnf: number
          amount_match: boolean
          client_name: string
          client_phone: string
          client_user_id: string
          created_at: string
          expires_at: string
          phone_match: boolean
          reference: string
          status: string
          topup_id: string
        }[]
      }
      read_email_batch: {
        Args: { batch_size: number; queue_name: string; vt: number }
        Returns: {
          message: Json
          msg_id: number
          read_ct: number
        }[]
      }
      ride_accept: {
        Args: { p_ride_id: string }
        Returns: {
          client_id: string
          completed_at: string | null
          created_at: string
          dest_lat: number | null
          dest_lng: number | null
          driver_earning_gnf: number
          driver_id: string | null
          fare_gnf: number
          hold_tx_id: string | null
          id: string
          metadata: Json | null
          mode: Database["public"]["Enums"]["ride_mode"]
          payment_tx_id: string | null
          pickup_lat: number
          pickup_lng: number
          platform_fee_gnf: number
          status: Database["public"]["Enums"]["ride_status"]
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "rides"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      ride_cancel: {
        Args: { p_reason?: string; p_ride_id: string }
        Returns: {
          client_id: string
          completed_at: string | null
          created_at: string
          dest_lat: number | null
          dest_lng: number | null
          driver_earning_gnf: number
          driver_id: string | null
          fare_gnf: number
          hold_tx_id: string | null
          id: string
          metadata: Json | null
          mode: Database["public"]["Enums"]["ride_mode"]
          payment_tx_id: string | null
          pickup_lat: number
          pickup_lng: number
          platform_fee_gnf: number
          status: Database["public"]["Enums"]["ride_status"]
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "rides"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      ride_complete: {
        Args: {
          p_actual_fare_gnf?: number
          p_commission_bps?: number
          p_ride_id: string
        }
        Returns: {
          client_id: string
          completed_at: string | null
          created_at: string
          dest_lat: number | null
          dest_lng: number | null
          driver_earning_gnf: number
          driver_id: string | null
          fare_gnf: number
          hold_tx_id: string | null
          id: string
          metadata: Json | null
          mode: Database["public"]["Enums"]["ride_mode"]
          payment_tx_id: string | null
          pickup_lat: number
          pickup_lng: number
          platform_fee_gnf: number
          status: Database["public"]["Enums"]["ride_status"]
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "rides"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      ride_confirm_pickup: {
        Args: { p_code: string; p_ride_id: string }
        Returns: {
          client_id: string
          completed_at: string | null
          created_at: string
          dest_lat: number | null
          dest_lng: number | null
          driver_earning_gnf: number
          driver_id: string | null
          fare_gnf: number
          hold_tx_id: string | null
          id: string
          metadata: Json | null
          mode: Database["public"]["Enums"]["ride_mode"]
          payment_tx_id: string | null
          pickup_lat: number
          pickup_lng: number
          platform_fee_gnf: number
          status: Database["public"]["Enums"]["ride_status"]
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "rides"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      ride_create: {
        Args: {
          p_dest_lat: number
          p_dest_lng: number
          p_driver_id?: string
          p_fare_gnf: number
          p_hold_tx_id: string
          p_mode: Database["public"]["Enums"]["ride_mode"]
          p_pickup_lat: number
          p_pickup_lng: number
        }
        Returns: {
          client_id: string
          completed_at: string | null
          created_at: string
          dest_lat: number | null
          dest_lng: number | null
          driver_earning_gnf: number
          driver_id: string | null
          fare_gnf: number
          hold_tx_id: string | null
          id: string
          metadata: Json | null
          mode: Database["public"]["Enums"]["ride_mode"]
          payment_tx_id: string | null
          pickup_lat: number
          pickup_lng: number
          platform_fee_gnf: number
          status: Database["public"]["Enums"]["ride_status"]
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "rides"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      ride_dispatch: { Args: { p_ride_id: string }; Returns: string }
      ride_integrity_check: { Args: { p_ride_id: string }; Returns: Json }
      ride_rate: {
        Args: {
          p_comment?: string
          p_direction?: Database["public"]["Enums"]["rating_direction"]
          p_ride_id: string
          p_score: number
        }
        Returns: string
      }
      ride_set_phase: {
        Args: { p_phase: string; p_ride_id: string }
        Returns: {
          client_id: string
          completed_at: string | null
          created_at: string
          dest_lat: number | null
          dest_lng: number | null
          driver_earning_gnf: number
          driver_id: string | null
          fare_gnf: number
          hold_tx_id: string | null
          id: string
          metadata: Json | null
          mode: Database["public"]["Enums"]["ride_mode"]
          payment_tx_id: string | null
          pickup_lat: number
          pickup_lng: number
          platform_fee_gnf: number
          status: Database["public"]["Enums"]["ride_status"]
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "rides"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      ride_start: {
        Args: { p_ride_id: string }
        Returns: {
          client_id: string
          completed_at: string | null
          created_at: string
          dest_lat: number | null
          dest_lng: number | null
          driver_earning_gnf: number
          driver_id: string | null
          fare_gnf: number
          hold_tx_id: string | null
          id: string
          metadata: Json | null
          mode: Database["public"]["Enums"]["ride_mode"]
          payment_tx_id: string | null
          pickup_lat: number
          pickup_lng: number
          platform_fee_gnf: number
          status: Database["public"]["Enums"]["ride_status"]
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "rides"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      show_limit: { Args: never; Returns: number }
      show_trgm: { Args: { "": string }; Returns: string[] }
      wallet_admin_credit: {
        Args: {
          p_amount_gnf: number
          p_provider_tx_id?: string
          p_reason: string
          p_user_id: string
        }
        Returns: {
          amount_gnf: number
          completed_at: string | null
          created_at: string
          description: string | null
          from_wallet_id: string | null
          id: string
          metadata: Json
          reference: string
          related_entity: string | null
          related_user_id: string | null
          status: Database["public"]["Enums"]["txn_status"]
          to_wallet_id: string | null
          type: Database["public"]["Enums"]["txn_type"]
        }
        SetofOptions: {
          from: "*"
          to: "wallet_transactions"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      wallet_capture: {
        Args: {
          p_actual_amount_gnf?: number
          p_description?: string
          p_hold_id: string
          p_to_party_type?: Database["public"]["Enums"]["party_type"]
          p_to_user_id?: string
        }
        Returns: {
          amount_gnf: number
          completed_at: string | null
          created_at: string
          description: string | null
          from_wallet_id: string | null
          id: string
          metadata: Json
          reference: string
          related_entity: string | null
          related_user_id: string | null
          status: Database["public"]["Enums"]["txn_status"]
          to_wallet_id: string | null
          type: Database["public"]["Enums"]["txn_type"]
        }
        SetofOptions: {
          from: "*"
          to: "wallet_transactions"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      wallet_ensure: { Args: { _party_type?: string }; Returns: string }
      wallet_hold: {
        Args: {
          p_amount_gnf: number
          p_description?: string
          p_reference?: string
        }
        Returns: {
          amount_gnf: number
          completed_at: string | null
          created_at: string
          description: string | null
          from_wallet_id: string | null
          id: string
          metadata: Json
          reference: string
          related_entity: string | null
          related_user_id: string | null
          status: Database["public"]["Enums"]["txn_status"]
          to_wallet_id: string | null
          type: Database["public"]["Enums"]["txn_type"]
        }
        SetofOptions: {
          from: "*"
          to: "wallet_transactions"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      wallet_internal_transfer: {
        Args: {
          p_amount_gnf: number
          p_description: string
          p_from_party_type: string
          p_from_user_id: string
          p_to_party_type: string
          p_to_user_id: string
        }
        Returns: {
          amount_gnf: number
          completed_at: string | null
          created_at: string
          description: string | null
          from_wallet_id: string | null
          id: string
          metadata: Json
          reference: string
          related_entity: string | null
          related_user_id: string | null
          status: Database["public"]["Enums"]["txn_status"]
          to_wallet_id: string | null
          type: Database["public"]["Enums"]["txn_type"]
        }
        SetofOptions: {
          from: "*"
          to: "wallet_transactions"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      wallet_release: {
        Args: { p_hold_id: string; p_reason?: string }
        Returns: {
          amount_gnf: number
          completed_at: string | null
          created_at: string
          description: string | null
          from_wallet_id: string | null
          id: string
          metadata: Json
          reference: string
          related_entity: string | null
          related_user_id: string | null
          status: Database["public"]["Enums"]["txn_status"]
          to_wallet_id: string | null
          type: Database["public"]["Enums"]["txn_type"]
        }
        SetofOptions: {
          from: "*"
          to: "wallet_transactions"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      wallet_topup_cancel: {
        Args: { p_reason?: string; p_topup_id: string }
        Returns: {
          agent_user_id: string | null
          amount_gnf: number
          cancelled_reason: string | null
          client_user_id: string
          confirmation_code: string
          confirmed_at: string | null
          created_at: string
          expires_at: string
          id: string
          matched_provider_transaction_id: string | null
          notes: string | null
          provider: string
          reference: string
          status: Database["public"]["Enums"]["topup_status"]
          transaction_id: string | null
          updated_at: string
          user_phone: string | null
        }
        SetofOptions: {
          from: "*"
          to: "topup_requests"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      wallet_topup_confirm: {
        Args: { p_code: string; p_topup_id: string }
        Returns: {
          amount_gnf: number
          completed_at: string | null
          created_at: string
          description: string | null
          from_wallet_id: string | null
          id: string
          metadata: Json
          reference: string
          related_entity: string | null
          related_user_id: string | null
          status: Database["public"]["Enums"]["txn_status"]
          to_wallet_id: string | null
          type: Database["public"]["Enums"]["txn_type"]
        }
        SetofOptions: {
          from: "*"
          to: "wallet_transactions"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      wallet_topup_create: {
        Args: { p_amount_gnf: number; p_client_user_id: string }
        Returns: {
          agent_user_id: string | null
          amount_gnf: number
          cancelled_reason: string | null
          client_user_id: string
          confirmation_code: string
          confirmed_at: string | null
          created_at: string
          expires_at: string
          id: string
          matched_provider_transaction_id: string | null
          notes: string | null
          provider: string
          reference: string
          status: Database["public"]["Enums"]["topup_status"]
          transaction_id: string | null
          updated_at: string
          user_phone: string | null
        }
        SetofOptions: {
          from: "*"
          to: "topup_requests"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      wallet_topup_om_create: {
        Args: { p_amount_gnf: number }
        Returns: {
          agent_user_id: string | null
          amount_gnf: number
          cancelled_reason: string | null
          client_user_id: string
          confirmation_code: string
          confirmed_at: string | null
          created_at: string
          expires_at: string
          id: string
          matched_provider_transaction_id: string | null
          notes: string | null
          provider: string
          reference: string
          status: Database["public"]["Enums"]["topup_status"]
          transaction_id: string | null
          updated_at: string
          user_phone: string | null
        }
        SetofOptions: {
          from: "*"
          to: "topup_requests"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      wallet_topup_om_credit: {
        Args: { p_event_id: string; p_topup_request_id: string }
        Returns: {
          amount_gnf: number
          completed_at: string | null
          created_at: string
          description: string | null
          from_wallet_id: string | null
          id: string
          metadata: Json
          reference: string
          related_entity: string | null
          related_user_id: string | null
          status: Database["public"]["Enums"]["txn_status"]
          to_wallet_id: string | null
          type: Database["public"]["Enums"]["txn_type"]
        }
        SetofOptions: {
          from: "*"
          to: "wallet_transactions"
          isOneToOne: true
          isSetofReturn: false
        }
      }
    }
    Enums: {
      admin_role: "super_admin" | "ops_admin" | "finance_admin"
      admin_user_status: "active" | "suspended"
      ai_assistant_kind: "admin" | "support" | "marche" | "fraud"
      ai_request_status: "ok" | "error" | "rate_limited" | "blocked"
      app_role:
        | "admin"
        | "user"
        | "client"
        | "driver"
        | "merchant"
        | "agent"
        | "recharge_agent"
        | "operations_admin"
        | "finance_admin"
        | "god_admin"
      approval_status: "pending" | "approved" | "rejected" | "cancelled"
      driver_application_decision:
        | "pending"
        | "approved"
        | "rejected"
        | "more_info"
      driver_presence: "offline" | "online" | "on_trip"
      driver_status: "pending" | "approved" | "rejected" | "suspended"
      driver_vehicle_type: "moto" | "toktok" | "livraison" | "auto"
      insight_confidence: "low" | "medium" | "high"
      insight_section:
        | "executive"
        | "behavior"
        | "mobility"
        | "wallet"
        | "marketplace"
        | "driver"
        | "merchant"
        | "fraud"
        | "growth"
        | "recommendation"
      listing_kind: "merchant" | "community" | "service"
      listing_status: "active" | "sold" | "paused" | "removed"
      message_channel: "whatsapp" | "sms" | "inapp"
      message_kind: "text" | "image" | "location" | "quick_reply"
      message_status:
        | "queued"
        | "sending"
        | "sent"
        | "delivered"
        | "read"
        | "failed"
      message_template:
        | "otp_code"
        | "welcome"
        | "topup_pending"
        | "topup_success"
        | "payment_success"
        | "refund"
        | "ride_confirmed"
        | "driver_assigned"
        | "delivery_completed"
        | "suspicious_activity"
      notification_channel: "email" | "sms" | "whatsapp" | "push" | "inapp"
      notification_priority: "critical" | "high" | "normal" | "low"
      notification_status:
        | "pending"
        | "sent"
        | "failed"
        | "suppressed"
        | "skipped"
      party_type: "client" | "driver" | "merchant" | "agent" | "master"
      rating_direction: "client_to_driver" | "driver_to_client"
      report_status: "open" | "reviewed" | "actioned" | "dismissed"
      ride_mode: "moto" | "toktok" | "food"
      ride_offer_status:
        | "pending"
        | "accepted"
        | "declined"
        | "missed"
        | "expired"
        | "cancelled"
      ride_status: "pending" | "in_progress" | "completed" | "cancelled"
      saved_place_kind: "home" | "work" | "favorite"
      topup_status:
        | "pending"
        | "confirmed"
        | "expired"
        | "cancelled"
        | "matched"
        | "needs_review"
        | "credited"
        | "failed"
      txn_status: "pending" | "completed" | "failed" | "reversed" | "cancelled"
      txn_type:
        | "topup"
        | "payment"
        | "refund"
        | "commission"
        | "payout"
        | "hold"
        | "capture"
        | "release"
        | "transfer"
        | "adjustment"
      wallet_status: "active" | "frozen" | "closed"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      admin_role: ["super_admin", "ops_admin", "finance_admin"],
      admin_user_status: ["active", "suspended"],
      ai_assistant_kind: ["admin", "support", "marche", "fraud"],
      ai_request_status: ["ok", "error", "rate_limited", "blocked"],
      app_role: [
        "admin",
        "user",
        "client",
        "driver",
        "merchant",
        "agent",
        "recharge_agent",
        "operations_admin",
        "finance_admin",
        "god_admin",
      ],
      approval_status: ["pending", "approved", "rejected", "cancelled"],
      driver_application_decision: [
        "pending",
        "approved",
        "rejected",
        "more_info",
      ],
      driver_presence: ["offline", "online", "on_trip"],
      driver_status: ["pending", "approved", "rejected", "suspended"],
      driver_vehicle_type: ["moto", "toktok", "livraison", "auto"],
      insight_confidence: ["low", "medium", "high"],
      insight_section: [
        "executive",
        "behavior",
        "mobility",
        "wallet",
        "marketplace",
        "driver",
        "merchant",
        "fraud",
        "growth",
        "recommendation",
      ],
      listing_kind: ["merchant", "community", "service"],
      listing_status: ["active", "sold", "paused", "removed"],
      message_channel: ["whatsapp", "sms", "inapp"],
      message_kind: ["text", "image", "location", "quick_reply"],
      message_status: [
        "queued",
        "sending",
        "sent",
        "delivered",
        "read",
        "failed",
      ],
      message_template: [
        "otp_code",
        "welcome",
        "topup_pending",
        "topup_success",
        "payment_success",
        "refund",
        "ride_confirmed",
        "driver_assigned",
        "delivery_completed",
        "suspicious_activity",
      ],
      notification_channel: ["email", "sms", "whatsapp", "push", "inapp"],
      notification_priority: ["critical", "high", "normal", "low"],
      notification_status: [
        "pending",
        "sent",
        "failed",
        "suppressed",
        "skipped",
      ],
      party_type: ["client", "driver", "merchant", "agent", "master"],
      rating_direction: ["client_to_driver", "driver_to_client"],
      report_status: ["open", "reviewed", "actioned", "dismissed"],
      ride_mode: ["moto", "toktok", "food"],
      ride_offer_status: [
        "pending",
        "accepted",
        "declined",
        "missed",
        "expired",
        "cancelled",
      ],
      ride_status: ["pending", "in_progress", "completed", "cancelled"],
      saved_place_kind: ["home", "work", "favorite"],
      topup_status: [
        "pending",
        "confirmed",
        "expired",
        "cancelled",
        "matched",
        "needs_review",
        "credited",
        "failed",
      ],
      txn_status: ["pending", "completed", "failed", "reversed", "cancelled"],
      txn_type: [
        "topup",
        "payment",
        "refund",
        "commission",
        "payout",
        "hold",
        "capture",
        "release",
        "transfer",
        "adjustment",
      ],
      wallet_status: ["active", "frozen", "closed"],
    },
  },
} as const
