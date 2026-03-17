Config = Config or {}
Config.Core = Config.Core or 'qb-core'
Config.Locale = 'pt-br' -- pt-br, en, etc
-- Webhook central de STAFF (exclusivo p/ relatórios STAFF)
Config.StaffWebhook = "ADD_STAFFWEBHOOK_HERE"

-- Jobs Padrão (Serão migrados para SQL se a tabela estiver vazia)
Config.AuthJobs = {
    ['police'] = {
        LogTitle       = 'Ponto Eletrônico - Policia',
        Color          = 3447003, -- Azul
        MinReportGrade = 0,
        Webhook        = "",
        ReportWebhook  = "",
        IconURL        = "https://cdn-icons-png.flaticon.com/512/2562/2562944.png"
    },
    ['ambulance'] = {
        LogTitle       = 'Ponto Eletrônico - Hospital',
        Color          = 15158332, -- Vermelho
        MinReportGrade = 0,
        Webhook        = "",
        ReportWebhook  = "",
        IconURL        = "https://cdn-icons-png.flaticon.com/512/2966/2966334.png"
    },
    ['mechanic'] = {
        LogTitle       = 'Ponto Eletrônico - Mecanica',
        Color          = 15105570, -- Laranja
        MinReportGrade = 0,
        Webhook        = "",
        ReportWebhook  = "",
        IconURL        = "https://cdn-icons-png.flaticon.com/512/2097/2097276.png"
    }
}