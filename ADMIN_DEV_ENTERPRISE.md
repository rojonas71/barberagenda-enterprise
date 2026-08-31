# Admin Dev Enterprise

O Dev Console foi ampliado para operação real da plataforma, mantendo a separação entre administração global e painel das empresas.

## Empresas
- KPIs globais de tenants, clientes e receita.
- Busca, filtros por status/plano e ordenação.
- Detalhes completos da empresa em drawer.
- Alteração de status e assinatura conforme RBAC.
- Exportação CSV e acesso rápido à agenda pública.

## Usuários
- KPIs de contas, bloqueios, confirmação e vínculos.
- Filtros por estado Auth e função na empresa.
- Bloquear/desbloquear, recuperação de senha e vínculo empresarial.
- Drawer técnico e exportação CSV.

## Planos
- Catálogo interno sem expor preços na landing.
- MRR estimado, assinantes, past due e limites.
- Recursos por plano, duplicação e edição.
- Plano em uso é desativado em vez de apagado à força.

## Suporte
- Fila com busca, categoria, prioridade e status.
- SLA calculado por prioridade.
- Responsável, notas internas e ações de resolução.
- Realtime e exportação CSV.

## Saúde
- Erros, warnings, incidentes e atividade 24h.
- Diagnóstico do schema via app_schema_health().
- Filtros de logs e detalhe de stack/metadata.
- Gestão do ciclo de incidentes.

## Auditoria
- Unifica developer_audit_logs e audit_logs.
- Filtros por origem, ação e período.
- Visualização de before/after e metadata.
- Exportação CSV.

## Configurações
- Modo manutenção, novos cadastros e mensagem global.
- Gestão de Administradores Dev.
- Matriz de permissões.
- Baseline de segurança e diagnóstico do banco.

## Permissões
- super_admin: controle integral.
- support: suporte e usuários.
- billing: planos e assinaturas.
- ops: empresas, saúde e configuração operacional.
- read_only: consulta global.

A landing continua sem tabela pública de planos e o projeto continua sem integração WhatsApp.
