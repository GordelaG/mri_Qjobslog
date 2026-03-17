local QBCore = exports[(Config and Config.Core) or 'qb-core']:GetCoreObject()

-- usa o mesmo gate de admin de sempre
if not IsStaff then
    _G.IsStaff = function(src)
        if QBCore and QBCore.Functions and QBCore.Functions.HasPermission then
            local ok, has = pcall(function()
                return QBCore.Functions.HasPermission(src, 'admin')
            end)
            if ok and has then return true end
        end
        local Player = QBCore and QBCore.Functions and QBCore.Functions.GetPlayer and QBCore.Functions.GetPlayer(src)
        if Player and Player.Functions and Player.Functions.HasPermission then
            local ok, has = pcall(function()
                return Player.Functions:HasPermission('admin')
            end)
            if ok and has then return true end
        end
        if IsPlayerAceAllowed and (IsPlayerAceAllowed(src, 'group.admin') or IsPlayerAceAllowed(src, 'command')) then
            return true
        end
        return false
    end
end

local RESOURCE  = GetCurrentResourceName()
local BKP_DIR   = 'logs_backup'

-- Função auxiliar para salvar arquivo
local function trySave(path, data)
    local ok = SaveResourceFile(RESOURCE, path, data, #data)
    return ok and true or false
end

-- /backupdutylogs -> Notifica que o SQL é o backup oficial
QBCore.Commands.Add('backupdutylogs', 'Notifica sobre backup SQL (ADMIN)', {}, false, function(src)
    if not IsStaff(src) then return end
    TriggerClientEvent('QBCore:Notify', src, 'O sistema agora é 100% SQL. Faça backup do seu Banco de Dados (mri_duty_logs).', 'primary', 5000)
end, 'admin')

-- /cleardutylogs -> zera a tabela SQL (apenas ADMIN)
QBCore.Commands.Add('cleardutylogs', 'Limpa toda a tabela mri_duty_logs (ADMIN)', {}, false, function(src)
    if not IsStaff(src) then
        if src > 0 then
            TriggerClientEvent('ox_lib:notify', src, {
                type = 'error', title = 'Duty Logs', description = 'Você não tem permissão.'
            })
        end
        return
    end

    exports.oxmysql:execute('TRUNCATE TABLE mri_duty_logs', {}, function(affected)
        if src > 0 then
            TriggerClientEvent('ox_lib:notify', src, {
                type = 'success', title = 'Duty Logs', description = 'Banco de dados de logs foi limpo!'
            })
        end
    end)
end, 'admin')
