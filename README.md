# 🚓 Duty Log System (QBCore + ox_lib + oxmysql)

Sistema avançado de controle de ponto e relatórios para QBCore, integrado com Discord e MySQL.

Permite que organizações controlem a entrada e saída de serviço dos seus membros, com logs automáticos, relatórios detalhados em CSV/Excel e configuração completa in-game.

---

## 🌟 Novidades (v2.0)

- **Nova UI (Dashboard):** Painel moderno para gerenciar tudo.
- **Banco de Dados SQL:** Adeus arquivos JSON! Todos os logs e configurações agora são salvos no MySQL (`oxmysql`).
- **Relatórios Unificados:** Embeds bonitos no Discord com arquivo `.xls` anexado na mesma mensagem.
- **Localização:** Suporte completo a tradução (padrão: `pt-br`) via arquivo JSON aninhado.
- **Relatório Individual:** Puxe a capivara completa de um único jogador.
- **Proteção de Dados:** Logs incluem Passaporte (CitizenID), Discord ID e Nome.

## 🧰 Funcionalidades

- **Logs Automáticos:** Detecta entrada/saída de serviço (mesmo se o servidor reiniciar ou script for reiniciado).
- **Interface In-Game:** Use `/logconfig` para adicionar/editar webhooks, cores e ícones de qualquer job.
- **Relatórios Completos:**
  - Histórico por Organização
  - Histórico por Jogador
  - Cálculo automático de duração
  - Exportação para Excel (.xls) direto no Discord
- **Migração Automática:** Se você tinha a versão antiga (JSON), ele tenta migrar as configs para SQL na primeira execução.

---

## 🕹️ Comandos

### Administrativos

| Comando                      | Permissão | Descrição                                                            |
| :--------------------------- | :-------- | :------------------------------------------------------------------- |
| `/logconfig`                 | Admin     | Abre o menu de gerenciamento de organizações (Add/Edit/Delete Jobs). |
| `/logtools`                  | Admin     | Ferramentas de manutenção (Limpeza de Logs antigos, Backup manual).  |
| `/relatoriojob [job] [dias]` | Admin     | Gera relatório de QUALQUER job (ex: `/relatoriojob police 30`).      |

### Gerenciais (Líderes)

| Comando                        | Permissão      | Descrição                                                    |
| :----------------------------- | :------------- | :----------------------------------------------------------- |
| `/relatorioorg [dias]`         | Grade Miníma\* | Gera relatório da _sua_ organização (ex: `/relatorioorg 7`). |
| `/relatorioplayer [id] [dias]` | Grade Mínima\* | Gera relatório individual de um membro da _sua_ org.         |

> \*A "Grade Mínima" é configurada in-game via `/logconfig`. Ex: Definir como 3 para que apenas Chefes possam puxar relatórios.

---

## 🛠️ Instalação

1. **Dependências:**
   - `qb-core`
   - `ox_lib`
   - `oxmysql`

2. **Banco de Dados:**
   - O script cria as tabelas automaticamente (`mri_orgs_config` e `mri_duty_logs`).
   - Se preferir, execute o `mri_Qjobslog.sql` manualmente.

3. **Configuração:**
   - Abra `shared/config.lua` para definir o Core e idioma.
   - Configure o **Webhook de Staff** (para logs administrativos) no `Config.StaffWebhook`.

---

## 🌍 Tradução

O sistema usa `locales/pt-br.json`. Você pode criar outros idiomas (ex: `en.json`) e alterar no `shared/config.lua`.

---

## � Estrutura

- **Client:** Escuta eventos de Duty e JobUpdate.
- **Server:** Processa logs, salva no MySQL, gera CSV e envia para Discord (Multipart Request).
- **Shared:** Carregador de Locale customizado e Configs.

---

## ✨ Créditos

**Autor:** Gordela | New Age Studios
**Refatoração SQL & Locale:** S&S STORE - SNOW DEVE

---
