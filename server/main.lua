local QBCore = exports[Config.Core]:GetCoreObject()
lib.locale()

local RESOURCE = GetCurrentResourceName()

-- Verifica e cria a tabela ao iniciar
-- Verifica e cria as tabelas ao iniciar
CreateThread(function()
    -- Tabela de Configuração
    exports.oxmysql:query([[
        CREATE TABLE IF NOT EXISTS `mri_orgs_config` (
            `job_name` varchar(50) NOT NULL,
            `webhook` text DEFAULT NULL,
            `report_webhook` text DEFAULT NULL,
            `min_grade` int(11) DEFAULT 0,
            `log_title` varchar(100) DEFAULT NULL,
            `color` int(11) DEFAULT 3447003,
            `icon_url` text DEFAULT NULL,
            PRIMARY KEY (`job_name`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    -- Tabela de Logs (existente)
    exports.oxmysql:query([[
        CREATE TABLE IF NOT EXISTS `mri_duty_logs` (
            `id` int(11) NOT NULL AUTO_INCREMENT,
            `job` varchar(50) DEFAULT NULL,
            `player_name` varchar(100) DEFAULT NULL,
            `citizenid` varchar(50) DEFAULT NULL,
            `grade` varchar(50) DEFAULT NULL,
            `discord_id` varchar(50) DEFAULT NULL,
            `status` varchar(50) DEFAULT NULL,
            `duration` int(11) DEFAULT 0,
            `created_at` timestamp NULL DEFAULT current_timestamp(),
            PRIMARY KEY (`id`),
            KEY `job_idx` (`job`),
            KEY `created_at_idx` (`created_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {}, function(result)
        -- Tenta adicionar coluna se não existir (Migration)
        exports.oxmysql:query('ALTER TABLE `mri_duty_logs` ADD COLUMN IF NOT EXISTS `citizenid` varchar(50) DEFAULT NULL AFTER `player_name`', {}, function() end)
    end)

    -- Carrega Configurações do SQL
    Wait(500)
    LoadOrgsFromSQL()
end)

-- ===== CONFIGURAÇÃO VIA SQL =====
function LoadOrgsFromSQL()
    local results = exports.oxmysql:executeSync('SELECT * FROM mri_orgs_config')
    
    if results and #results > 0 then
        -- Limpa config atual para evitar duplicatas erradas
        Config.AuthJobs = {}
        for _, row in ipairs(results) do
            if row.job_name then
                Config.AuthJobs[row.job_name] = {
                    Webhook        = row.webhook,
                    ReportWebhook  = row.report_webhook,
                    MinReportGrade = row.min_grade,
                    LogTitle       = row.log_title,
                    Color          = row.color,
                    IconURL        = row.icon_url
                }
            end
        end
        print('[Duty Logs] Configurações de organizações carregadas do SQL.')
    else
        -- Se estiver vazio, migra o Config.AuthJobs padrão (se houver) para o SQL
        if Config.AuthJobs and next(Config.AuthJobs) then
            print('[Duty Logs] Migrando Config.AuthJobs inicial para o SQL...')
            for job, v in pairs(Config.AuthJobs) do
                local logTitle = v.LogTitle or ('Logs ' .. job)
                exports.oxmysql:insert('INSERT INTO mri_orgs_config (job_name, webhook, report_webhook, min_grade, log_title, color, icon_url) VALUES (?, ?, ?, ?, ?, ?, ?)',
                    { job, v.Webhook or '', v.ReportWebhook or '', v.MinReportGrade or 0, logTitle, v.Color or 3447003, v.IconURL or '' })
            end
        end
    end
end

local Timers = {}

local function FormatDuration(sec)
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    local s = sec % 60
    local out = ''
    if h > 0 then out = out .. h .. 'h ' end
    if m > 0 then out = out .. m .. 'm ' end
    if s > 0 then out = out .. s .. 's' end
    return out ~= '' and out or '0s'
end

-- pega webhook por job
local function GetWebhook(job)
    return Config.AuthJobs[job] and Config.AuthJobs[job].Webhook or nil
end

-- Formata data para o padrão solicitado: 10:00 31/01/2026
local function FormatDateLog(timestamp)
    return os.date('%H:%M %d/%m/%Y', timestamp)
end

-- envia ENTRADA, retorna messageId se possível
-- envia ENTRADA, retorna messageId se possível
local function SendOnDutyLogToDiscord(src, playerName, job, jobGrade, discordId, citizenId)
    -- SQL Insert
    exports.oxmysql:insert('INSERT INTO mri_duty_logs (job, player_name, citizenid, grade, discord_id, status, duration) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { job, playerName, citizenId, jobGrade, discordId, 'Entrou em Serviço', 0 })

    local webhook = GetWebhook(job)
    if not webhook then return nil end

    local fields = {
        { name = locale('field.collaborator'), value = ("%s\n`%s: %s`"):format(playerName, locale('field.passport'), citizenId), inline = true },
        { name = locale('field.player_info'), value = ("%s: <@%s>\n`ID: %s`"):format(locale('field.discord'), discordId, src), inline = true },
        { name = locale('field.grade'), value = ("%s | %s"):format(job, jobGrade), inline = false },
        { name = locale('field.start'), value = FormatDateLog(os.time()), inline = true }
    }

    -- Adiciona wait=true para esperar o ID da mensagem
    local messageId = nil

    PerformHttpRequest(webhook .. "?wait=true", function(err, text, headers)
        if err == 200 and text then
            local data = json.decode(text)
            if data and data.id then
                messageId = data.id 
                -- Tenta atualizar o timer se ele já existir (caso de race condition)
                local pId = QBCore.Functions.GetPlayer(src)
                if pId then
                    local cid = pId.PlayerData.citizenid
                    if Timers[cid] then Timers[cid].messageId = messageId end
                end
            end
        end
    end, 'POST', json.encode({
        username = (Config.AuthJobs[job] and Config.AuthJobs[job].LogTitle) or 'Duty Log',
        embeds = {{
            color = (Config.AuthJobs[job] and Config.AuthJobs[job].Color) or 3447003,
            title = locale('log.started_duty'),
            fields = fields,
            footer = { text = "Dynasty RP • " .. os.date('%d/%m/%Y %X') },
            thumbnail = { url = (Config.AuthJobs[job] and Config.AuthJobs[job].IconURL) or '' },
        }}
    }), { ['Content-Type'] = 'application/json' })

    return messageId 
end

-- envia SAÍDA (Edita mensagem ou cria nova)
local function SendOffDutyLogToDiscord(job, seconds, playerName, jobGrade, discordId, originalMessageId, citizenId, startTimeStr)
    -- SQL Insert
    exports.oxmysql:insert('INSERT INTO mri_duty_logs (job, player_name, citizenid, grade, discord_id, status, duration) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { job, playerName, citizenId, jobGrade, discordId, 'Saiu de Serviço', seconds or 0 })

    local webhook = GetWebhook(job)
    if not webhook then return end

    local readable = FormatDuration(seconds)
    local endTimeStr = FormatDateLog(os.time())

    local fields = {
        { name = locale('field.total_time'), value = ("```yaml\n%s\n```"):format(readable), inline = false },
        { name = locale('field.collaborator'), value = ("%s\n`%s: %s`"):format(playerName, locale('field.passport'), citizenId), inline = true },
        { name = locale('field.player_info'), value = ("%s: <@%s>"):format(locale('field.discord'), discordId), inline = true },
        { name = locale('field.grade'), value = ("%s | %s"):format(job, jobGrade), inline = true },
        { name = locale('field.entered'), value = startTimeStr, inline = true },
        { name = locale('field.exited'), value = endTimeStr, inline = true }
    }

    local payload = {
        username = (Config.AuthJobs[job] and Config.AuthJobs[job].LogTitle) or 'Duty Log',
        embeds = {{
            color = 15158332, -- Vermelho/Laranja para saída
            title = locale('log.finished_duty'),
            fields = fields,
            footer = { text = "Dynasty RP • " .. os.date('%d/%m/%Y %X') },
            thumbnail = { url = (Config.AuthJobs[job] and Config.AuthJobs[job].IconURL) or '' },
        }}
    }

    if originalMessageId then
        -- EDITA a mensagem original (PATCH)
        PerformHttpRequest(webhook .. "/messages/" .. originalMessageId, function(err, text, headers) 
            if err ~= 200 then
                 -- Se falhar a edição (ex: mensagem apagada), manda uma nova
                 PerformHttpRequest(webhook, function() end, 'POST', json.encode(payload), { ['Content-Type'] = 'application/json' })
            end
        end, 'PATCH', json.encode(payload), { ['Content-Type'] = 'application/json' })
    else
        -- Manda NOVA mensagem
        PerformHttpRequest(webhook, function() end, 'POST', json.encode(payload), { ['Content-Type'] = 'application/json' })
    end
end

-- ENVIA ARQUIVO (MULTIPART)
-- ENVIA ARQUIVO + EMBED (MULTIPART UNIFICADO)
local function UploadCSVToDiscord(webhook, content, filename, jsonPayload)
    if not webhook then return end
    local boundary = "------------------------Boundary" .. os.time() .. math.random(1000,9999)
    
    local body = {}

    -- Parte 1: JSON (Embeds, Username, Avatar, Attachments link)
    if jsonPayload then
        -- Vincula o arquivo como anexo 0
        if not jsonPayload.attachments then
            jsonPayload.attachments = { { id = 0, filename = filename } }
        end

        table.insert(body, "--" .. boundary)
        table.insert(body, 'Content-Disposition: form-data; name="payload_json"')
        table.insert(body, 'Content-Type: application/json')
        table.insert(body, '')
        table.insert(body, json.encode(jsonPayload))
    end

    -- Parte 2: Arquivo (files[0])
    table.insert(body, "--" .. boundary)
    table.insert(body, 'Content-Disposition: form-data; name="files[0]"; filename="' .. filename .. '"')
    table.insert(body, 'Content-Type: application/vnd.ms-excel') -- Tenta forçar excel pra evitar preview de texto
    table.insert(body, '')
    table.insert(body, content)

    -- Rodapé
    table.insert(body, '--' .. boundary .. '--')

    PerformHttpRequest(webhook, function(err, text, headers) 
        --if err ~= 200 then print('[DutyLog] Erro upload unificado: '..err) end
    end, 'POST', table.concat(body, "\r\n"), {
        ["Content-Type"] = "multipart/form-data; boundary=" .. boundary
    })
end

-- ============ EVENTOS ============
-- player carregou → se já estiver de serviço, loga "userjoined"
RegisterNetEvent('kael-dutylog:server:userjoined', function(job, duty)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or not job or not duty then return end
    if not Config.AuthJobs[job] then return end

    local citizenid = Player.PlayerData.citizenid
    if not Timers[citizenid] and duty then
        local entry = { 
            job = job, 
            startTime = os.time(), 
            startDate = FormatDateLog(os.time()), -- Agora usa formato custom
            messageId = nil 
        }
        Timers[citizenid] = entry

        local name = ('%s %s'):format(Player.PlayerData.charinfo.firstname, Player.PlayerData.charinfo.lastname)
        local grade = Player.PlayerData.job.grade.name
        local discord = (QBCore.Functions.GetIdentifier(src, 'discord') or ''):gsub('discord:', '')
        
        -- Chama função unificada
        SendOnDutyLogToDiscord(src, name, job, grade, discord, citizenid)
    end
end)

-- DUTY ON
RegisterNetEvent('kael-dutylog:server:onDuty', function(job)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or not job or not Config.AuthJobs[job] then return end

    local citizenid = Player.PlayerData.citizenid
    if Timers[citizenid] then return end -- já estava cronometrando

    local entry = { 
        job = job, 
        startTime = os.time(), 
        startDate = FormatDateLog(os.time()),
        messageId = nil 
    }
    Timers[citizenid] = entry

    local name = ('%s %s'):format(Player.PlayerData.charinfo.firstname, Player.PlayerData.charinfo.lastname)
    local grade = Player.PlayerData.job.grade.name
    local discord = (QBCore.Functions.GetIdentifier(src, 'discord') or ''):gsub('discord:', '')

    SendOnDutyLogToDiscord(src, name, job, grade, discord, citizenid)
end)

-- DUTY OFF
RegisterNetEvent('kael-dutylog:server:offDuty', function(job)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or not job or not Config.AuthJobs[job] then return end

    local citizenid = Player.PlayerData.citizenid
    local t = Timers[citizenid]
    if not t then return end

    local elapsed = os.time() - t.startTime
    local name = ('%s %s'):format(Player.PlayerData.charinfo.firstname, Player.PlayerData.charinfo.lastname)
    local grade = Player.PlayerData.job.grade.name
    local discord = (QBCore.Functions.GetIdentifier(src, 'discord') or ''):gsub('discord:', '')

    local msgId = t.messageId -- Pega o ID salvo
    local startDate = t.startDate or FormatDateLog(t.startTime)

    Timers[citizenid] = nil
    SendOffDutyLogToDiscord(job, elapsed, name, grade, discord, msgId, citizenid, startDate)
end)

-- QUEDA / SAÍDA DO SERVIDOR
AddEventHandler('playerDropped', function()
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid
    local t = Timers[citizenid]
    if not t then return end

    local job = t.job
    if not Config.AuthJobs[job] then Timers[citizenid] = nil return end

    local elapsed = os.time() - t.startTime
    local name = ('%s %s'):format(Player.PlayerData.charinfo.firstname, Player.PlayerData.charinfo.lastname)
    local grade = Player.PlayerData.job.grade.name
    local discord = (QBCore.Functions.GetIdentifier(src, 'discord') or ''):gsub('discord:', '')

    local msgId = t.messageId
    local startDate = t.startDate or FormatDateLog(t.startTime)

    Timers[citizenid] = nil
    SendOffDutyLogToDiscord(job, elapsed, name, grade, discord, msgId, citizenid, startDate)
end)

-- === RELATÓRIO POR ORG, COM PERMISSÃO DE GRADE ===
QBCore.Commands.Add('relatorioorg', locale('cmd.relatorioorg_help'), {
    { name = 'dias', help = locale('cmd.days_param') }
}, false, function(source, args)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    local job = Player.PlayerData.job and Player.PlayerData.job.name
    if not job or not Config.AuthJobs[job] then
        if src > 0 then TriggerClientEvent('QBCore:Notify', src, locale('error_job_not_authorized'), 'error') end
        return
    end

    local jobCfg = Config.AuthJobs[job]
    local gradeLevel = 0
    if Player.PlayerData.job and Player.PlayerData.job.grade then
        -- QBCore/Qbox: pode ser number ou table com .level
        if type(Player.PlayerData.job.grade) == "table" then
            gradeLevel = tonumber(Player.PlayerData.job.grade.level or 0) or 0
        else
            gradeLevel = tonumber(Player.PlayerData.job.grade or 0) or 0
        end
    end

    local minG = tonumber(jobCfg.MinReportGrade or 0) or 0
    if gradeLevel < minG then
        if src > 0 then TriggerClientEvent('QBCore:Notify', src, locale('error_min_grade', minG), 'error') end
        return
    end

    -- Janela de dias
    local onlyDays = tonumber(args[1] or 0)
    -- Query detalhada (adicionado citizenid)
    local query = 'SELECT player_name, citizenid, discord_id, grade, duration, UNIX_TIMESTAMP(created_at) as exit_ts FROM mri_duty_logs WHERE job = ? AND status = "Saiu de Serviço"'
    local queryArgs = { job }

    if onlyDays and onlyDays > 0 then
        query = query .. ' AND created_at >= NOW() - INTERVAL ? DAY'
        table.insert(queryArgs, onlyDays)
    end
    
    query = query .. ' ORDER BY created_at DESC'

    exports.oxmysql:execute(query, queryArgs, function(results)
        if not results or #results == 0 then
            if src > 0 then TriggerClientEvent('QBCore:Notify', src, locale('error_no_logs'), 'error') end
            return
        end

        local csvLines = { "Passaporte;Nome;Discord;Cargo;Job;Entrada;Saida;Duracao" }
        local totals   = {} -- tabela para somar totais pro Discord
        local any      = false

        for _, row in ipairs(results) do
            local exitTs  = row.exit_ts
            local entryTs = row.exit_ts - row.duration
            local durFmt  = FormatDuration(row.duration)
            
            local dEntry  = os.date("%d/%m/%Y %H:%M:%S", entryTs)
            local dExit   = os.date("%d/%m/%Y %H:%M:%S", exitTs)

            -- CSV Detalhado: Passaporte, Nome, Discord, Grade, Job, Entrada, Saida, Duracao
            table.insert(csvLines, ("%s;%s;%s;%s;%s;%s;%s;%s"):format(
                row.citizenid or 'N/A',
                row.player_name, 
                row.discord_id or 'N/A', 
                row.grade or 'N/A', 
                job,
                dEntry, 
                dExit, 
                durFmt
            ))

            -- Acumula total para o Discord
            totals[row.player_name] = (totals[row.player_name] or 0) + row.duration
        end

        -- Salva arquivo CSV (Detalhado) mas com extensão .xls para evitar preview do Discord
        local csvContent = table.concat(csvLines, "\n")
        local fileName = ("reports/Relatorio_%s_%s.xls"):format(job, os.date("%Y-%m-%d_%H-%M-%S"))
        SaveResourceFile(GetCurrentResourceName(), fileName, csvContent, #csvContent)
        
        if src > 0 then 
            TriggerClientEvent('QBCore:Notify', src, locale('success_report_generated', fileName), 'success') 
        end

        -------------------------------------------------------
        -- DADOS DO EXECUTOR (Quem pediu o relatório)
        -------------------------------------------------------
        local executorName = ('%s %s'):format(Player.PlayerData.charinfo.firstname, Player.PlayerData.charinfo.lastname)
        local executorCid  = Player.PlayerData.citizenid
        local executorGrade = Player.PlayerData.job.grade.name .. " (" .. gradeLevel .. ")"
        local executorDiscord = (QBCore.Functions.GetIdentifier(src, 'discord') or ''):gsub('discord:', '')
        
        -- Lógica de Datas do Relatório
        local periodTitle = locale('report_title_complete')
        local dateFrom    = os.date("%d/%m", results[#results].exit_ts) -- Data do registro mais antigo
        local dateTo      = os.date("%d/%m")

        if onlyDays and onlyDays > 0 then
            periodTitle = locale('report_title_days', onlyDays)
            dateFrom    = os.date("%d/%m", os.time() - (onlyDays * 86400))
        end

        local embedFields = {
            { name = locale('field_exported_by'), value = executorName, inline = true },
            { name = locale('field_executor_info'), value = ("%s: `%s`\n%s: <@%s>"):format(locale('field_passport'), executorCid, locale('field_discord'), executorDiscord), inline = true },
            { name = locale('field_grade'), value = executorGrade, inline = true },
            -- Novos campos solicitados
            { name = locale('field_period', periodTitle), value = ("Dia: %s\nAté: %s"):format(dateFrom, dateTo), inline = false },
            { name = locale('field_file'), value = locale('field_file_desc'), inline = false }
        }

        -- Mensagem de "Sucesso" no título/descrição
        local desc = locale('desc_organization', job)

        -- escolhe webhook específico da org (fallback para Webhook normal)
        local webhook = jobCfg.ReportWebhook or jobCfg.Webhook
        if not webhook or webhook == "" then
            if src > 0 then TriggerClientEvent('QBCore:Notify', src, locale('error_webhook_not_configured'), 'error') end
            return
        end
        
        -- UPLOAD UNIFICADO (Arquivo + Embed na mesma mensagem)
        local payload = {
            username = jobCfg.LogTitle or ('Relatório ' .. job),
            embeds = {{
                color = jobCfg.Color or 3447003,
                title = locale('log_report_generated'),
                description = desc,
                fields = embedFields,
                footer = { text = "Dynasty RP • Sistema de Ponto" },
                thumbnail = { url = jobCfg.IconURL or "" },
            }}
        }

        UploadCSVToDiscord(webhook, csvContent, "Relatorio_"..job..".xls", payload)

        if src > 0 then TriggerClientEvent('QBCore:Notify', src, locale('success_report_sent'), 'success') end
    end)
end, 'user')

-- /relatorioplayer <citizenid> [dias]
QBCore.Commands.Add('relatorioplayer', locale('cmd.relatorioplayer_help'), {
    { name = 'citizenid', help = locale('cmd.citizenid_param') },
    { name = 'dias', help = locale('cmd.days_param') }
}, false, function(source, args)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    local cidTarget = args[1]
    if not cidTarget then 
        TriggerClientEvent('QBCore:Notify', src, locale('error_invalid_citizenid'), 'error')
        return
    end

    local job = Player.PlayerData.job and Player.PlayerData.job.name
    if not job or not Config.AuthJobs[job] then
        TriggerClientEvent('QBCore:Notify', src, locale('error_job_not_authorized'), 'error')
        return
    end
    
    local jobCfg = Config.AuthJobs[job]
    local gradeLevel = 0
    if Player.PlayerData.job and Player.PlayerData.job.grade then
        if type(Player.PlayerData.job.grade) == "table" then
            gradeLevel = tonumber(Player.PlayerData.job.grade.level or 0) or 0
        else
            gradeLevel = tonumber(Player.PlayerData.job.grade or 0) or 0
        end
    end

    local minG = tonumber(jobCfg.MinReportGrade or 0) or 0
    if gradeLevel < minG then
        TriggerClientEvent('QBCore:Notify', src, locale('error_min_grade', minG), 'error')
        return
    end

    local onlyDays = tonumber(args[2] or 0)
    
    -- Query filtrada por CITIZENID
    local query = 'SELECT player_name, citizenid, discord_id, grade, duration, UNIX_TIMESTAMP(created_at) as exit_ts FROM mri_duty_logs WHERE job = ? AND citizenid = ? AND status = "Saiu de Serviço"'
    local queryArgs = { job, cidTarget }

    if onlyDays and onlyDays > 0 then
        query = query .. ' AND created_at >= NOW() - INTERVAL ? DAY'
        table.insert(queryArgs, onlyDays)
    end
    
    query = query .. ' ORDER BY created_at DESC'

    exports.oxmysql:execute(query, queryArgs, function(results)
        if not results or #results == 0 then
            TriggerClientEvent('QBCore:Notify', src, locale('error_no_logs_citizenid'), 'error')
            return
        end

        local csvLines = { "Passaporte;Nome;Discord;Cargo;Job;Entrada;Saida;Duracao" }
        local any      = false
        
        -- Pega info do primeiro resultado para o header do Embed
        local targetName = results[1].player_name or "Desconhecido"
        local targetDiscord = results[1].discord_id or "N/A"

        for _, row in ipairs(results) do
            local exitTs  = row.exit_ts
            local entryTs = row.exit_ts - row.duration
            local durFmt  = FormatDuration(row.duration)
            
            local dEntry  = os.date("%d/%m/%Y %H:%M:%S", entryTs)
            local dExit   = os.date("%d/%m/%Y %H:%M:%S", exitTs)

            table.insert(csvLines, ("%s;%s;%s;%s;%s;%s;%s;%s"):format(
                row.citizenid or 'N/A',
                row.player_name, 
                row.discord_id or 'N/A', 
                row.grade or 'N/A', 
                job,
                dEntry, 
                dExit, 
                durFmt
            ))
        end

        local csvContent = table.concat(csvLines, "\n")
        local fileName = ("reports/RelatorioIndividual_%s_%s_%s.xls"):format(cidTarget, job, os.date("%Y-%m-%d_%H-%M-%S"))
        SaveResourceFile(GetCurrentResourceName(), fileName, csvContent, #csvContent)
        
        TriggerClientEvent('QBCore:Notify', src, locale('success_individual_report'), 'success')

        -- Executor Info
        local executorName = ('%s %s'):format(Player.PlayerData.charinfo.firstname, Player.PlayerData.charinfo.lastname)
        local executorCid  = Player.PlayerData.citizenid
        local executorDiscord = (QBCore.Functions.GetIdentifier(src, 'discord') or ''):gsub('discord:', '')
        
        -- Datas
        local periodTitle = "Relatório Completo Exportado"
        local dateFrom    = os.date("%d/%m", results[#results].exit_ts)
        local dateTo      = os.date("%d/%m")
        if onlyDays and onlyDays > 0 then
            periodTitle = ("Relatório exportado de %d dias"):format(onlyDays)
            dateFrom    = os.date("%d/%m", os.time() - (onlyDays * 86400))
        end

        local embedFields = {
            { name = locale('field_collaborator'), value = targetName, inline = true },
            { name = locale('field_passport'), value = ("`%s`"):format(cidTarget), inline = true },
            { name = locale('field_discord'), value = ("<@%s>"):format(targetDiscord), inline = true },
            
            { name = locale('field_period', periodTitle), value = ("Dia: %s\nAté: %s"):format(dateFrom, dateTo), inline = false },
            { name = locale('field_exported_by'), value = ("%s \nPassaporte: `%s`\n<@%s>"):format(executorName, executorCid, executorDiscord), inline = false },
            { name = locale('field_file'), value = locale('field_file_desc'), inline = false }
        }

        local desc = locale('desc_organization', job)

        local webhook = jobCfg.ReportWebhook or jobCfg.Webhook
        if not webhook or webhook == "" then return end
        
        local title = locale('log.report_individual')
        local payload = {
            username = jobCfg.LogTitle or ('Relatório ' .. job),
            embeds = {{
                color = jobCfg.Color or 3447003,
                title = title,
                description = desc,
                fields = embedFields,
                footer = { text = "Dynasty RP • Sistema de Ponto" },
                thumbnail = { url = jobCfg.IconURL or "" },
            }}
        }

        UploadCSVToDiscord(webhook, csvContent, "Relatorio_"..cidTarget..".xls", payload)
    end)
end, 'user')

-- /relatoriojob ADMIN
QBCore.Commands.Add('relatoriojob', locale('cmd.relatoriojob_help'), {
    { name = 'job',  help = locale('cmd.job_param') },
    { name = 'dias', help = locale('cmd.days_param') }
}, true, function(source, args)
    local src  = source
    local job  = tostring(args[1] or ''):lower()
    local days = tonumber(args[2] or 0)

    -- gate por admin (server-side)
    if not IsStaff(src) then
        if src > 0 then TriggerClientEvent('QBCore:Notify', src, 'Sem permissão.', 'error') end
        return
    end

    if job == '' then
        if src > 0 then TriggerClientEvent('QBCore:Notify', src, locale('error.usage_relatoriojob'), 'error') end
        return
    end

    local jobCfg = Config.AuthJobs[job]
    if not jobCfg then
        if src > 0 then TriggerClientEvent('QBCore:Notify', src, locale('error.job_not_found', job), 'error') end
        return
    end

    -- Query detalhada
    local query = 'SELECT player_name, citizenid, discord_id, grade, duration, UNIX_TIMESTAMP(created_at) as exit_ts FROM mri_duty_logs WHERE job = ? AND status = "Saiu de Serviço"'
    local queryArgs = { job }

    if days and days > 0 then
        query = query .. ' AND created_at >= NOW() - INTERVAL ? DAY'
        table.insert(queryArgs, days)
    end
    
    query = query .. ' ORDER BY created_at DESC'

    exports.oxmysql:execute(query, queryArgs, function(results)
        if not results or #results == 0 then
            if src > 0 then TriggerClientEvent('QBCore:Notify', src, locale('error.no_logs'), 'error') end
            return
        end

        local csvLines = { "Passaporte;Nome;Discord;Cargo;Job;Entrada;Saida;Duracao" }
        local totals   = {} 

        for _, row in ipairs(results) do
            local exitTs  = row.exit_ts
            local entryTs = row.exit_ts - row.duration
            local durFmt  = FormatDuration(row.duration)
            
            local dEntry  = os.date("%d/%m/%Y %H:%M:%S", entryTs)
            local dExit   = os.date("%d/%m/%Y %H:%M:%S", exitTs)

            -- CSV Detalhado
            table.insert(csvLines, ("%s;%s;%s;%s;%s;%s;%s;%s"):format(
                row.citizenid or 'N/A',
                row.player_name, 
                row.discord_id or 'N/A', 
                row.grade or 'N/A', 
                job,
                dEntry, 
                dExit, 
                durFmt
            ))

             -- Acumula total para o Discord
             totals[row.player_name] = (totals[row.player_name] or 0) + row.duration
        end

        local csvContent = table.concat(csvLines, "\n")
        local fileName = ("reports/RelatorioAdmin_%s_%s.xls"):format(job, os.date("%Y-%m-%d_%H-%M-%S"))
        SaveResourceFile(GetCurrentResourceName(), fileName, csvContent, #csvContent)
        
        if src > 0 then 
            TriggerClientEvent('QBCore:Notify', src, locale('success.report_generated', fileName), 'success') 
        end
        
        -------------------------------------------------------
        -- DADOS DO EXECUTOR (ADMIN)
        -------------------------------------------------------
        local Player = QBCore.Functions.GetPlayer(src)
        local executorName = "Console"
        local executorCid  = "N/A"
        local executorGrade = "Admin"
        local executorDiscord = ""
        
        if Player then
             executorName = ('%s %s'):format(Player.PlayerData.charinfo.firstname, Player.PlayerData.charinfo.lastname)
             executorCid  = Player.PlayerData.citizenid
             executorDiscord = (QBCore.Functions.GetIdentifier(src, 'discord') or ''):gsub('discord:', '')
             -- Tenta pegar grade se tiver job, senao deixa Admin
             if Player.PlayerData.job and Player.PlayerData.job.grade then
                local gName = Player.PlayerData.job.grade.name or ""
                executorGrade = "STAFF (" .. gName .. ")"
             else
                executorGrade = "STAFF"
             end
        end

        -- Lógica de Datas do Relatório (STAFF)
        local periodTitle = locale('report_title.complete')
        local dateFrom    = os.date("%d/%m", results[#results].exit_ts) 
        local dateTo      = os.date("%d/%m")

        if days and days > 0 then
            periodTitle = locale('report_title.days', days)
            dateFrom    = os.date("%d/%m", os.time() - (days * 86400))
        end

        local embedFields = {
            { name = locale('field.exported_by'), value = executorName, inline = true },
            { name = locale('field.executor_info'), value = ("%s: `%s`\n%s: <@%s>"):format(locale('field.passport'), executorCid, locale('field.discord'), executorDiscord), inline = true },
            { name = locale('field.grade'), value = executorGrade, inline = true },
            -- Novos campos
            { name = locale('field.period', periodTitle), value = ("Dia: %s\nAté: %s"):format(dateFrom, dateTo), inline = false },
            { name = locale('field.file'), value = locale('field.file_desc'), inline = false }
        }

        local desc = locale('desc.organization', job)

        --STAFF WEBHOOK EXCLUSIVO (sem fallback)
        local webhook = Config.StaffWebhook
        if not webhook or webhook == "" then
            if src > 0 then TriggerClientEvent('QBCore:Notify', src, locale('error.staff_webhook_not_configured'), 'error') end
            return
        end

        -- UPLOAD STAFF UNIFICADO
        local payload = {
            username = (jobCfg.LogTitle or 'Relatório') .. ' | STAFF',
            embeds = {{
                color = jobCfg.Color or 3447003,
                title = locale('log.report_staff'),
                description = desc,
                fields = embedFields,
                footer = { text = "Dynasty RP • Sistema de Ponto" },
                thumbnail = { url = jobCfg.IconURL or "" },
            }}
        }

        UploadCSVToDiscord(webhook, csvContent, "RelatorioAdmin_"..job..".xls", payload)

        if src > 0 then TriggerClientEvent('QBCore:Notify', src, locale('success.staff_report'), 'success') end
    end)
end, 'admin')

-- ===== ox_lib Callbacks (Gestão SQL) =====
lib.callback.register('dutylogcfg:isStaff', function(src)
    return IsStaff(src)
end)

lib.callback.register('dutylogcfg:getAll_v2', function(src)
    if not IsStaff(src) then return { ok = false, reason = 'no_perm' } end
    -- Sincroniza do banco antes de mandar
    LoadOrgsFromSQL()
    
    -- Converte para LISTA (Array) para garantir integridade no Client
    local listData = {}
    if Config.AuthJobs then
        for k, v in pairs(Config.AuthJobs) do
            local item = {
                jobName = k, -- a chave vira uma propriedade
                LogTitle = v.LogTitle,
                Color = v.Color,
                MinReportGrade = v.MinReportGrade,
                Webhook = v.Webhook,
                ReportWebhook = v.ReportWebhook,
                IconURL = v.IconURL
            }
            table.insert(listData, item)
        end
    end
    
    -- ENVIAR COMO STRING JSON (Bulletproof)
    -- Isso evita que o FiveM/ox_lib "coma" o array durante o transporte
    local jsonStr = json.encode(listData)
    return { ok = true, json = jsonStr }
end)

lib.callback.register('dutylogcfg:saveOrg', function(src, key, data)
    if not IsStaff(src) then return { ok = false, reason = 'no_perm' } end
    if not key or key == '' or type(data) ~= 'table' then
        return { ok = false, reason = 'bad_data' }
    end

    local webhook       = tostring(data.Webhook or '')
    local rWebhook      = tostring(data.ReportWebhook or '')
    local minGrade      = tonumber(data.MinReportGrade or 0) or 0
    local logTitle      = tostring(data.LogTitle or ('Logs ' .. key))
    local color         = tonumber(data.Color or 3447003) or 3447003
    local iconURL       = tostring(data.IconURL or '')

    -- Salva no SQL (Upsert)
    exports.oxmysql:execute([[
        INSERT INTO mri_orgs_config (job_name, webhook, report_webhook, min_grade, log_title, color, icon_url)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
        webhook = VALUES(webhook), report_webhook = VALUES(report_webhook), min_grade = VALUES(min_grade),
        log_title = VALUES(log_title), color = VALUES(color), icon_url = VALUES(icon_url)
    ]], { key, webhook, rWebhook, minGrade, logTitle, color, iconURL })

    -- Atualiza memória
    Config.AuthJobs[key] = {
        Webhook = webhook, ReportWebhook = rWebhook, MinReportGrade = minGrade,
        LogTitle = logTitle, Color = color, IconURL = iconURL
    }

    return { ok = true }
end)

lib.callback.register('dutylogcfg:deleteOrg', function(src, key)
    if not IsStaff(src) then return { ok = false, reason = 'no_perm' } end
    
    exports.oxmysql:execute('DELETE FROM mri_orgs_config WHERE job_name = ?', { key })
    Config.AuthJobs[key] = nil
    
    return { ok = true }
end)

