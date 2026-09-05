export type Business = {
  id: string
  name: string
  slug: string
  phone: string | null
  address: string | null
  logo_url: string | null
  banner_url?: string | null
  opening_time: string
  closing_time: string
  slot_interval: number
  timezone?: string
  booking_advance_days?: number
  min_booking_notice_minutes?: number
  cancellation_notice_hours?: number
  booking_enabled?: boolean
  auto_confirm_bookings?: boolean
  allow_waitlist?: boolean
  public_booking_message?: string | null
  platform_status?: 'active' | 'suspended' | 'archived'
}

export type Service = {
  id: string
  business_id: string
  name: string
  description: string | null
  price: number
  duration_minutes: number
  active: boolean
}

export type Professional = {
  id: string
  business_id: string
  name: string
  bio: string | null
  photo_url: string | null
  phone?: string | null
  email?: string | null
  specialty?: string | null
  active: boolean
  commission_percent?: number
}

export type Appointment = {
  id: string
  business_id: string
  professional_id: string
  service_id: string
  client_id?: string | null
  client_name: string
  client_phone: string
  appointment_date: string
  start_time: string
  end_time: string
  status: 'pending' | 'confirmed' | 'completed' | 'cancelled' | 'no_show'
  notes: string | null
  created_at: string
  discount_amount?: number
  final_amount?: number | null
  payment_status?: 'unpaid' | 'paid' | 'refunded'
  payment_method?: string | null
  services?: { name: string; price: number } | null
  professionals?: { name: string; commission_percent?: number } | null
}

export type ClientSummary = {
  id: string
  name: string
  phone: string
  email: string | null
  notes: string | null
  birthday: string | null
  tags: string[]
  source: string
  marketing_opt_in: boolean
  blocked: boolean
  total_appointments: number
  completed_appointments: number
  cancelled_appointments: number
  no_show_appointments: number
  total_spent: number
  average_ticket: number
  first_appointment_date: string | null
  last_appointment_date: string | null
  next_appointment_date: string | null
  days_since_last: number | null
  favorite_service_name: string | null
  favorite_professional_name: string | null
  last_contact_at: string | null
  updated_at: string
}

export type ClientHistoryItem = {
  appointment_id: string
  appointment_date: string
  start_time: string
  end_time: string
  status: 'pending' | 'confirmed' | 'completed' | 'cancelled' | 'no_show'
  service_name: string
  service_price: number
  professional_name: string
  appointment_notes: string | null
}

export type ClientNote = {
  id: string
  business_id: string
  client_id: string
  content: string
  created_by: string | null
  created_at: string
}

export type WeeklyHour = {
  id?: string
  business_id?: string
  professional_id?: string
  day_of_week: number
  is_open: boolean
  open_time: string
  close_time: string
}

export type ScheduleBlock = {
  id: string
  business_id: string
  professional_id: string | null
  start_date: string
  end_date: string
  start_time: string | null
  end_time: string | null
  reason: string
  created_at: string
  professionals?: { name: string } | null
}

export type FinancialTransaction = {
  id: string
  business_id: string
  appointment_id: string | null
  type: 'income' | 'expense'
  category: string
  description: string
  amount: number
  payment_method: string | null
  status: 'pending' | 'paid' | 'cancelled'
  transaction_date: string
  created_at: string
}

export type BusinessMember = {
  id: string
  business_id: string
  user_id: string
  role: 'owner' | 'manager' | 'receptionist' | 'professional'
  display_name: string | null
  phone: string | null
  active: boolean
  professional_id?: string | null
  created_at: string
}

export type BusinessInvite = {
  id: string
  business_id: string
  email: string
  role: 'manager' | 'receptionist' | 'professional'
  token: string
  status: 'pending' | 'accepted' | 'cancelled' | 'expired'
  expires_at: string
  created_at: string
}



export type WaitlistEntry = {
  id: string
  business_id: string
  service_id: string
  professional_id: string | null
  client_name: string
  client_phone: string
  desired_date: string
  preferred_period: 'any' | 'morning' | 'afternoon' | 'evening'
  status: 'waiting' | 'contacted' | 'booked' | 'cancelled' | 'expired'
  notes: string | null
  source: 'public' | 'staff'
  created_at: string
  updated_at: string
}


