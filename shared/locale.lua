-- Carrega sistema de Locale customizado para suportar aninhamento (dot notation)
local langCode = Config.Locale or 'pt-br'
local content = LoadResourceFile(GetCurrentResourceName(), 'locales/' .. langCode .. '.json')
local LangData = {}

if content then
    LangData = json.decode(content) or {}
else
    print('^1[Duty Logs] Erro: Arquivo de linguagem nao encontrado: ' .. langCode .. '.json^0')
end

-- Função unificada para buscar chave (com ou sem ponto)
function locale(key, ...)
    if not key then return "nil" end

    local current = LangData
    -- Navega pela estrutura usando gmatch
    for part in key:gmatch("[^%.]+") do
        if type(current) == 'table' then
            current = current[part]
        else
            current = nil
            break
        end
    end

    if type(current) == 'string' then
        -- Só formata se houver argumentos, evitando erro com % em strings estáticas
        if select('#', ...) > 0 then
            return current:format(...)
        end
        return current
    end

    return current or key
end

function _U(key, ...)
    return locale(key, ...)
end
