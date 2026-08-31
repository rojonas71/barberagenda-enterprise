import {
  Activity,
  ArrowRight,
  BarChart3,
  CalendarCheck2,
  CalendarDays,
  CheckCircle2,
  CircleDollarSign,
  Clock3,
  Database,
  FileClock,
  Gauge,
  ListOrdered,
  LockKeyhole,
  MonitorSmartphone,
  Scissors,
  Settings2,
  ShieldCheck,
  Smartphone,
  Sparkles,
  UserCheck,
  Users,
  Zap,
} from 'lucide-react'
import { Link } from 'react-router-dom'

const features = [
  { icon: CalendarDays, title: 'Agenda inteligente', text: 'Agendamentos online, CRUD completo, prevenção de conflitos, status, bloqueios e atualização em tempo real.' },
  { icon: Users, title: 'CRM de clientes', text: 'Histórico, recorrência, tags, VIP, no-show, ticket médio, observações e visão completa do relacionamento.' },
  { icon: FileClock, title: 'Disponibilidade avançada', text: 'Jornada individual, intervalos, folgas, férias, feriados, bloqueios e regras específicas por profissional.' },
  { icon: CircleDollarSign, title: 'Financeiro integrado', text: 'Receitas, despesas, descontos, formas de pagamento, comissões e resultado operacional em um só painel.' },
  { icon: BarChart3, title: 'Dashboard e relatórios', text: 'Indicadores de operação, faturamento, ticket médio, serviços mais realizados e performance da equipe.' },
  { icon: UserCheck, title: 'Equipe e permissões', text: 'Owner, gerente, recepção e profissional com acessos separados e controle por função.' },
  { icon: ListOrdered, title: 'Lista de espera', text: 'Capture clientes quando a agenda estiver cheia e acompanhe contato, conversão ou cancelamento.' },
  { icon: Settings2, title: 'Configuração do negócio', text: 'Horários, regras de antecedência, cancelamento, agenda pública, endereço e identidade da empresa.' },
  { icon: Smartphone, title: 'Mobile + PC', text: 'Experiência responsiva para celular, tablet, notebook e desktop, com PWA instalável.' },
  { icon: Zap, title: 'Tempo real', text: 'Agenda, clientes e operação sincronizados pelo Supabase Realtime sem depender de recarregar a página.' },
]

const faqs = [
  ['O cliente precisa criar conta para agendar?', 'Não. A agenda pública foi pensada para reduzir atrito: o cliente escolhe serviço, profissional, data e horário e informa os dados necessários para concluir o agendamento.'],
  ['Funciona para mais de um profissional?', 'Sim. Cada profissional pode ter jornada, disponibilidade, comissão, bloqueios e agenda próprios dentro da mesma empresa.'],
  ['Posso usar no celular e no computador?', 'Sim. O painel é responsivo e funciona em celular, tablet, notebook e desktop. A aplicação também possui estrutura de PWA instalável.'],
  ['Como o sistema evita horários duplicados?', 'As regras de disponibilidade e os intervalos ocupados são validados no banco, reduzindo o risco de dois agendamentos conflitarem no mesmo período.'],
  ['Os funcionários precisam ter o mesmo acesso do proprietário?', 'Não. O sistema possui funções e permissões separadas para proprietário, gerente, recepção e profissional.'],
  ['Os dados ficam separados por empresa?', 'Sim. A arquitetura multiempresa utiliza políticas de segurança no Supabase para restringir o acesso aos dados de cada negócio conforme o usuário autenticado e sua função.'],
]

export function HomePage() {
  return (
    <main className="page-shell landing-v5">
      <header className="topbar container landing-topbar">
        <Link className="brand landing-brand" to="/" aria-label="BarberAgenda - início">
          <span className="brand-icon"><Scissors size={20} /></span>
          <span>BarberAgenda</span>
        </Link>

        <nav className="landing-nav" aria-label="Navegação principal">
          <a href="#recursos">Recursos</a>
          <a href="#como-funciona">Como funciona</a>
          <a href="#para-quem">Para quem</a>
          <a href="#seguranca">Segurança</a>
          <a href="#faq">FAQ</a>
        </nav>

        <div className="landing-header-actions">
          <Link className="button button-ghost" to="/login">Entrar</Link>
          <Link className="button button-primary landing-header-cta" to="/login?mode=register">Criar conta</Link>
        </div>
      </header>

      <section className="container landing-hero">
        <div className="landing-hero-copy">
          <span className="eyebrow"><Sparkles size={14}/> GESTÃO COMPLETA PARA BARBEARIAS E SALÕES</span>
          <h1>Organize sua agenda. Conheça seus clientes. Controle sua operação.</h1>
          <p className="landing-lead">Centralize agendamentos, equipe, clientes, financeiro, disponibilidade e relatórios em uma plataforma profissional preparada para acompanhar o dia a dia do seu negócio.</p>

          <div className="hero-actions landing-hero-actions">
            <Link className="button button-primary landing-main-cta" to="/login?mode=register">
              Criar minha conta <ArrowRight size={18}/>
            </Link>
            <a className="button button-secondary" href="#como-funciona">Ver como funciona</a>
          </div>

          <div className="landing-trust-list">
            <span><CheckCircle2 size={17}/> Agenda online 24 horas</span>
            <span><CheckCircle2 size={17}/> Mobile e PC</span>
            <span><CheckCircle2 size={17}/> Dados separados por empresa</span>
            <span><CheckCircle2 size={17}/> Atualização em tempo real</span>
          </div>
        </div>

        <div className="landing-product-preview" aria-label="Prévia do painel BarberAgenda">
          <div className="landing-preview-window">
            <div className="landing-preview-bar">
              <div className="landing-preview-dots"><span/><span/><span/></div>
              <div className="landing-preview-address">app.barberagenda / painel</div>
              <div className="landing-live"><span/> AO VIVO</div>
            </div>
            <div className="landing-preview-body">
              <aside className="landing-preview-sidebar">
                <div className="landing-mini-brand"><Scissors size={17}/></div>
                <span className="active"><Gauge size={16}/></span>
                <span><CalendarDays size={16}/></span>
                <span><Users size={16}/></span>
                <span><BarChart3 size={16}/></span>
                <span><Settings2 size={16}/></span>
              </aside>
              <div className="landing-preview-content">
                <div className="landing-preview-head">
                  <div><small>VISÃO GERAL</small><strong>Operação do dia</strong></div>
                  <span className="landing-preview-status"><Activity size={14}/> Realtime</span>
                </div>
                <div className="landing-preview-kpis">
                  <article><CalendarCheck2 size={18}/><small>Agenda</small><strong>Organizada</strong></article>
                  <article><Users size={18}/><small>Clientes</small><strong>CRM ativo</strong></article>
                  <article><CircleDollarSign size={18}/><small>Financeiro</small><strong>Integrado</strong></article>
                </div>
                <div className="landing-preview-agenda">
                  <div className="landing-preview-section-title"><strong>Próximos horários</strong><span>Tempo real</span></div>
                  <div className="landing-preview-row"><b>09:00</b><span><i/> Cliente agendado</span><em>Confirmado</em></div>
                  <div className="landing-preview-row"><b>10:00</b><span><i/> Atendimento</span><em>Confirmado</em></div>
                  <div className="landing-preview-row"><b>11:30</b><span><i/> Horário disponível</span><em className="available">Livre</em></div>
                </div>
              </div>
            </div>
          </div>
          <div className="landing-floating-card floating-one"><ShieldCheck size={18}/><div><small>Segurança</small><strong>RLS + permissões</strong></div></div>
          <div className="landing-floating-card floating-two"><MonitorSmartphone size={18}/><div><small>Acesso</small><strong>Mobile + PC</strong></div></div>
        </div>
      </section>

      <section className="landing-capability-strip">
        <div className="container landing-capability-grid">
          <div><CalendarCheck2/><span><strong>Agenda online</strong><small>Agendamento público e operação interna</small></span></div>
          <div><Zap/><span><strong>Tempo real</strong><small>Alterações refletidas sem recarregar</small></span></div>
          <div><ShieldCheck/><span><strong>Controle de acesso</strong><small>Permissões por função e empresa</small></span></div>
          <div><BarChart3/><span><strong>Gestão baseada em dados</strong><small>Indicadores para acompanhar o negócio</small></span></div>
        </div>
      </section>

      <section className="section container landing-problem-section">
        <div className="section-head landing-centered-head">
          <span className="eyebrow">MENOS IMPROVISO, MAIS CONTROLE</span>
          <h2>O sistema organiza o que normalmente fica espalhado</h2>
          <p>Em vez de depender de várias ferramentas desconectadas, concentre a operação em um único ambiente.</p>
        </div>
        <div className="landing-problem-grid">
          <article><Clock3/><div><h3>Horários desorganizados</h3><p>Disponibilidade, bloqueios e agenda ficam estruturados por profissional.</p></div></article>
          <article><Users/><div><h3>Clientes sem histórico</h3><p>Tenha CRM com visitas, preferências, recorrência, no-show e relacionamento.</p></div></article>
          <article><CircleDollarSign/><div><h3>Financeiro separado da agenda</h3><p>Relacione atendimentos, valores, comissões, receitas e despesas.</p></div></article>
          <article><BarChart3/><div><h3>Decisões sem indicadores</h3><p>Acompanhe desempenho e comportamento da operação em dashboards e relatórios.</p></div></article>
        </div>
      </section>

      <section id="recursos" className="section landing-soft-section">
        <div className="container">
          <div className="section-head landing-section-split">
            <div><span className="eyebrow">BARBERAGENDA ENTERPRISE</span><h2>Uma operação completa, não apenas um calendário</h2></div>
            <p>Recursos conectados para atender desde a rotina da recepção até a visão estratégica do proprietário.</p>
          </div>
          <div className="feature-grid landing-feature-grid">
            {features.map(({ icon: Icon, title, text }) => (
              <article className="feature-card landing-feature-card" key={title}>
                <span className="landing-feature-icon"><Icon size={21}/></span>
                <h3>{title}</h3>
                <p>{text}</p>
              </article>
            ))}
          </div>
        </div>
      </section>

      <section id="como-funciona" className="section container landing-how-section">
        <div className="section-head landing-centered-head">
          <span className="eyebrow">DO CADASTRO AO ATENDIMENTO</span>
          <h2>Um fluxo simples para o cliente e completo para a equipe</h2>
        </div>
        <div className="landing-steps">
          <article><span>01</span><div><CalendarDays/><h3>Configure sua operação</h3><p>Cadastre empresa, serviços, profissionais, jornadas, regras e disponibilidade.</p></div></article>
          <article><span>02</span><div><Smartphone/><h3>Compartilhe sua agenda</h3><p>O cliente acessa a página pública pelo celular e consulta os horários disponíveis.</p></div></article>
          <article><span>03</span><div><CalendarCheck2/><h3>Receba o agendamento</h3><p>O novo horário entra na agenda e fica disponível para a equipe acompanhar em tempo real.</p></div></article>
          <article><span>04</span><div><BarChart3/><h3>Acompanhe a operação</h3><p>Histórico, clientes, financeiro e indicadores evoluem junto com os atendimentos.</p></div></article>
        </div>
      </section>

      <section id="para-quem" className="section landing-audience-section">
        <div className="container landing-audience-layout">
          <div className="landing-audience-copy">
            <span className="eyebrow">FEITO PARA QUEM ATENDE COM HORÁRIO MARCADO</span>
            <h2>Adapte o BarberAgenda à rotina do seu negócio.</h2>
            <p>A estrutura atende operações individuais ou equipes com vários profissionais, mantendo agenda, clientes e gestão no mesmo lugar.</p>
            <div className="landing-audience-tags">
              <span>Barbearias</span><span>Salões</span><span>Studio Hair</span><span>Manicure</span><span>Estética</span><span>Profissionais autônomos</span>
            </div>
          </div>
          <div className="landing-audience-cards">
            <article><UserCheck/><div><h3>Profissional autônomo</h3><p>Organize sua própria agenda e clientes sem depender de processos manuais.</p></div></article>
            <article><Users/><div><h3>Equipe com recepção</h3><p>Divida funções e mantenha disponibilidade e agendamentos centralizados.</p></div></article>
            <article><Gauge/><div><h3>Gestão em crescimento</h3><p>Ganhe visão operacional, financeira e de performance conforme o negócio evolui.</p></div></article>
          </div>
        </div>
      </section>

      <section id="seguranca" className="section container landing-security-section">
        <div className="landing-security-card">
          <div className="landing-security-copy">
            <span className="eyebrow">ARQUITETURA DE PRODUÇÃO</span>
            <h2>Estrutura preparada para operar com segurança e controle.</h2>
            <p>O projeto combina autenticação, políticas de acesso, banco PostgreSQL, tempo real e separação de responsabilidades entre frontend e backend.</p>
            <div className="landing-security-checks">
              <span><LockKeyhole size={17}/> Autenticação Supabase</span>
              <span><ShieldCheck size={17}/> Row Level Security</span>
              <span><Database size={17}/> PostgreSQL</span>
              <span><Activity size={17}/> Realtime</span>
              <span><UserCheck size={17}/> RBAC por função</span>
            </div>
          </div>
          <div className="landing-security-stack">
            <div><small>INTERFACE</small><strong>React + TypeScript</strong><span>Mobile • Tablet • PC</span></div>
            <ArrowRight size={18}/>
            <div><small>PLATAFORMA</small><strong>Supabase</strong><span>Auth • RLS • Realtime • RPC</span></div>
            <ArrowRight size={18}/>
            <div><small>DADOS</small><strong>PostgreSQL</strong><span>Multiempresa • Regras de negócio</span></div>
          </div>
        </div>
      </section>

      <section id="faq" className="section landing-faq-section">
        <div className="container landing-faq-layout">
          <div className="landing-faq-copy">
            <span className="eyebrow">PERGUNTAS FREQUENTES</span>
            <h2>O que você precisa saber antes de começar.</h2>
            <p>A plataforma foi desenhada para deixar o agendamento simples para o cliente e a gestão completa para quem administra.</p>
          </div>
          <div className="landing-faq-list">
            {faqs.map(([question, answer]) => (
              <details key={question}>
                <summary>{question}<span>+</span></summary>
                <p>{answer}</p>
              </details>
            ))}
          </div>
        </div>
      </section>

      <section className="section container landing-final-cta-section">
        <div className="landing-final-cta">
          <div>
            <span className="eyebrow">SUA OPERAÇÃO EM UM SÓ LUGAR</span>
            <h2>Comece com sua agenda e evolua sua gestão.</h2>
            <p>Crie sua conta, configure sua empresa e tenha uma base profissional para organizar atendimentos, clientes, equipe e operação.</p>
          </div>
          <div className="landing-final-actions">
            <Link className="button button-primary" to="/login?mode=register">Criar minha conta <ArrowRight size={18}/></Link>
            <Link className="button button-secondary" to="/login">Já tenho uma conta</Link>
          </div>
        </div>
      </section>

      <footer className="footer landing-footer">
        <div className="container landing-footer-grid">
          <div><div className="brand"><span className="brand-icon"><Scissors size={18}/></span> BarberAgenda</div><p>Gestão profissional para negócios que trabalham com hora marcada.</p></div>
          <div><strong>Produto</strong><a href="#recursos">Recursos</a><a href="#como-funciona">Como funciona</a><a href="#seguranca">Segurança</a></div>
          <div><strong>Acesso</strong><Link to="/login">Entrar no painel</Link><Link to="/login?mode=register">Criar conta</Link></div>
        </div>
        <div className="container landing-footer-bottom">BarberAgenda • Agenda, clientes, equipe e gestão em uma única plataforma.</div>
      </footer>
    </main>
  )
}
