import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom'
import { HomePage } from './pages/HomePage'
import { BookingPage } from './pages/BookingPage'
import { LoginPage } from './pages/LoginPage'
import { AdminPage } from './pages/AdminPage'
import { ClientsPage } from './pages/ClientsPage'
import { OnboardingPage } from './pages/OnboardingPage'
import { ServicesPage } from './pages/ServicesPage'
import { ProfessionalsPage } from './pages/ProfessionalsPage'
import { SettingsPage } from './pages/SettingsPage'
import { DashboardPage } from './pages/DashboardPage'
import { FinancePage } from './pages/FinancePage'
import { ReportsPage } from './pages/ReportsPage'
import { AvailabilityPage } from './pages/AvailabilityPage'
import { TeamPage } from './pages/TeamPage'
import { InvitePage } from './pages/InvitePage'
import { MaintenanceGate } from './components/MaintenanceGate'
import { DevAdminLayout } from './components/DevAdminLayout'
import { DevLoginPage } from './pages/dev/DevLoginPage'
import { DevDashboardPage } from './pages/dev/DevDashboardPage'
import { DevBusinessesPage } from './pages/dev/DevBusinessesPage'
import { DevUsersPage } from './pages/dev/DevUsersPage'
import { DevPlansPage } from './pages/dev/DevPlansPage'
import { DevSupportPage } from './pages/dev/DevSupportPage'
import { DevHealthPage } from './pages/dev/DevHealthPage'
import { DevSettingsPage } from './pages/dev/DevSettingsPage'
import { SupportCenterPage } from './pages/SupportCenterPage'
import { WaitlistPage } from './pages/WaitlistPage'
import { OfflineStatus } from './components/OfflineStatus'
import './styles.css'

export default function App() {
  return (
    <BrowserRouter>
      <MaintenanceGate>
      <Routes>
        <Route path="/" element={<HomePage />} />
        <Route path="/b/:slug" element={<BookingPage />} />
        <Route path="/login" element={<LoginPage />} />
        <Route path="/onboarding" element={<OnboardingPage />} />
        <Route path="/painel" element={<AdminPage />} />
        <Route path="/painel/dashboard" element={<DashboardPage />} />
        <Route path="/painel/clientes" element={<ClientsPage />} />
        <Route path="/painel/servicos" element={<ServicesPage />} />
        <Route path="/painel/profissionais" element={<ProfessionalsPage />} />
        <Route path="/painel/configuracoes" element={<SettingsPage />} />
        <Route path="/painel/disponibilidade" element={<AvailabilityPage />} />
        <Route path="/painel/financeiro" element={<FinancePage />} />
        <Route path="/painel/relatorios" element={<ReportsPage />} />
        <Route path="/painel/equipe" element={<TeamPage />} />
        <Route path="/painel/suporte" element={<SupportCenterPage />} />
        <Route path="/painel/lista-espera" element={<WaitlistPage />} />
        <Route path="/convite/:token" element={<InvitePage />} />
        <Route path="/dev-admin/login" element={<DevLoginPage />} />
        <Route path="/dev-admin" element={<DevAdminLayout />}>
          <Route index element={<DevDashboardPage />} />
          <Route path="empresas" element={<DevBusinessesPage />} />
          <Route path="usuarios" element={<DevUsersPage />} />
          <Route path="planos" element={<DevPlansPage />} />
          <Route path="suporte" element={<DevSupportPage />} />
          <Route path="saude" element={<DevHealthPage />} />
          <Route path="configuracoes" element={<DevSettingsPage />} />
        </Route>
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
      </MaintenanceGate>
      <OfflineStatus />
    </BrowserRouter>
  )
}
