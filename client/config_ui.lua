local function toggleNuiFrame(shouldShow)
    SetNuiFocus(shouldShow, shouldShow)
    SendNUIMessage({
        action = 'setVisible',
        data = { visible = shouldShow }
    })
    if shouldShow then
        -- Refresh orgs when opening
        local isStaff = lib.callback.await('dutylogcfg:isStaff', false)
        if not isStaff then 
            toggleNuiFrame(false)
            return lib.notify({ description = 'Sem permissão', type = 'error' }) 
        end

        local resp = lib.callback.await('dutylogcfg:getAll_v2', false)
        if resp and resp.ok then
            SendNUIMessage({
                action = 'refreshOrgs'
            })
        end
    end
end

RegisterCommand('logconfig', function()
    toggleNuiFrame(true)
end, false)

RegisterNUICallback('hideFrame', function(_, cb)
    toggleNuiFrame(false)
    cb({})
end)

RegisterNUICallback('getOrgs', function(_, cb)
    local resp = lib.callback.await('dutylogcfg:getAll_v2', false)
    if resp and resp.ok then
        cb(resp.json)
    else
        cb({})
    end
end)

RegisterNUICallback('createOrg', function(data, cb)
    local key = data.jobName
    local payload = {
        LogTitle = data.LogTitle,
        Color = data.Color,
        IconURL = data.IconURL,
        MinReportGrade = data.MinReportGrade,
        Webhook = data.Webhook,
        ReportWebhook = data.ReportWebhook
    }
    local save = lib.callback.await('dutylogcfg:saveOrg', false, key, payload)
    cb(save)
    if save and save.ok then
        lib.notify({ description = 'Organização criada com sucesso', type = 'success' })
    else
        lib.notify({ description = 'Erro ao criar organização', type = 'error' })
    end
end)

RegisterNUICallback('updateOrg', function(data, cb)
    local key = data.jobName
    local payload = data.data
    local save = lib.callback.await('dutylogcfg:saveOrg', false, key, payload)
    cb(save)
    if save and save.ok then
        lib.notify({ description = 'Organização atualizada', type = 'success' })
    else
        lib.notify({ description = 'Erro ao atualizar', type = 'error' })
    end
end)

RegisterNUICallback('deleteOrg', function(data, cb)
    local del = lib.callback.await('dutylogcfg:deleteOrg', false, data.jobName)
    cb(del)
    if del and del.ok then
        lib.notify({ description = 'Organização removida', type = 'success' })
    else
        lib.notify({ description = 'Erro ao remover', type = 'error' })
    end
end)

RegisterNUICallback('clearLogs', function(_, cb)
    ExecuteCommand('cleardutylogs')
    cb('ok')
    lib.notify({ description = 'Limpeza solicitada', type = 'info' })
end)

RegisterNUICallback('backupLogs', function(_, cb)
    ExecuteCommand('backupdutylogs')
    cb('ok')
    lib.notify({ description = 'Backup solicitado', type = 'info' })
end)
