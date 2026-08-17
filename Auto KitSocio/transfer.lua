--[[
    AUTO TRANSFER + ORGANIZAR
    Criador: vitorvtx
    Comando: /transfer
    v3.7 - cofre: confirma no chat, se falhar repete (sem delay 4s)
]]

script_name("Auto Transfer")
script_author("vitorvtx")
script_version("3.7")



require "lib.moonloader"
local imgui = require "mimgui"
local ffi = require "ffi"
local sampev = require "lib.samp.events"

local C = {
    delay = 45,
    dist = 1.6,
    walk_ms = 12000,
    stuck = 22,
    open_ms = 1500,
    close_ms = 800,
    after_open = 60,
    org_max = 40,
    wait_confirm = 6000,
    cofre_retry = 3,
}


-- numeros do dialog do cofre BRP
local COFRE_NUM = { M4 = 14, DESERT = 6, DEAGLE = 6 }

-- tipo: 1 COFRE | 2 PORTAMALAS | 3 CAIXA (ID so na 3)
local S = {
    menu = false,
    rodando = false,
    parar = false,
    id_origem = 0,
    id_destino = 0,
    orig_tipo = 1,
    dest_tipo = 1,
    item_tipo = 1,
    id_org = 0,
    item_org = 1,
    qtd = 1,
    feita = 0,
    status = "Parado",
    pos = imgui.ImVec2(100, 80),
    last_chat = "",
    chat_flag = false,
}

local buf_ori = imgui.new.char[12]("")
local buf_des = imgui.new.char[12]("")
local buf_qtd = imgui.new.char[8]("1")
local buf_item = imgui.new.char[32]("M4")
local buf_org = imgui.new.char[12]("")
local buf_org_item = imgui.new.char[32]("M4")
local buf_cofre_num = imgui.new.char[8]("")

ffi.cdef[[void keybd_event(unsigned char,unsigned char,unsigned long,unsigned long);]]
local UP = 0x0002
local VK = { F = 0x46, W = 0x57, N = 0x4E, ENTER = 0x0D, ESC = 0x1B }

local function now() return os.clock() * 1000 end
local function key(vk, d)
    ffi.C.keybd_event(vk, 0, 0, 0); wait(12)
    ffi.C.keybd_event(vk, 0, UP, 0); wait(d or C.delay)
end
local function kdown(vk) ffi.C.keybd_event(vk, 0, 0, 0) end
local function kup(vk) ffi.C.keybd_event(vk, 0, UP, 0) end
local function soltar()
    kup(VK.W)
    pcall(function()
        setGameKeyState(1,0) setGameKeyState(2,0) setGameKeyState(3,0) setGameKeyState(4,0)
    end)
end
local function set_status(t) S.status = t or "..." end
local function nome_tipo(t)
    if t == 1 then return "COFRE" end
    if t == 2 then return "PORTAMALAS" end
    if t == 3 then return "CAIXA" end
    return "?"
end

function sampev.onServerMessage(color, text)
    if type(text) == "string" and text ~= "" then
        S.last_chat = text
        S.chat_flag = true
    end
end

-- SO no cofre: espera msg no chat
-- true = sucesso | false = falhou / timeout (deve repetir)
local function esperar_confirmacao_cofre()
    set_status("Esperando confirmacao (cofre)...")
    S.chat_flag = false
    S.last_chat = ""
    local t0 = now()
    while now() - t0 < C.wait_confirm do
        if S.parar then return false end
        if S.chat_flag then
            local u = (S.last_chat or ""):upper()
            S.chat_flag = false
            -- ignora spam do servidor
            if u:find("AGUARDE DE 15") or u:find("MANDARAM MENSAGEM") then
                -- continua esperando
            elseif u:find("NAO ") or u:find("NÃO ") or u:find("ERRO")
                or u:find("INVALIDO") or u:find("INVÁLIDO") or u:find("INSUFICIENTE")
                or u:find("NAO TEM") or u:find("NÃO TEM") or u:find("SEM ")
                or u:find("FALHA") or u:find("NEGADO") then
                set_status("Cofre: falhou no chat")
                return false
            else
                -- qualquer outra msg apos o comando = confirma
                set_status("Cofre: confirmado")
                return true
            end
        end
        wait(80)
    end
    set_status("Cofre: sem confirmacao")
    return false
end


local function get_3d_info(i)
    local ok, a, b, c, d, e = pcall(function()
        if sampGet3dTextInfoById then return sampGet3dTextInfoById(i) end
        return nil
    end)
    if not ok then return nil end
    return a, b, c, d, e
end

local function achar_caixa(id)
    local needle = ("CAIXA DE ITENS " .. tostring(id)):upper()
    for i = 0, 2048 do
        local okd, def = pcall(function()
            return sampIs3dTextDefined and sampIs3dTextDefined(i)
        end)
        if okd and def then
            local a, b, c, d, e = get_3d_info(i)
            local text, x, y, z
            if type(a) == "string" then
                text = a
                if type(c)=="number" and type(d)=="number" and type(e)=="number" then
                    x,y,z = c,d,e
                elseif type(b)=="number" and type(c)=="number" and type(d)=="number" then
                    x,y,z = b,c,d
                end
            end
            if text and text:upper():find(needle, 1, true) and x then
                return true, x, y, z
            end
        end
    end
    return false, 0, 0, 0
end

local function heading(tx, ty)
    local px, py = getCharCoordinates(PLAYER_PED)
    local ok, h = pcall(function() return getHeadingFromVector2d(tx-px, ty-py) end)
    if ok and h then return h end
    return -math.deg(math.atan2(ty-py, tx-px)) + 90
end

local function andar(x, y, z, dist_ok)
    dist_ok = dist_ok or C.dist
    local fim, lx, ly, stk, first = now()+C.walk_ms, 0, 0, 0, true
    soltar(); wait(15)
    while now() < fim do
        if S.parar then soltar(); return false end
        if not isCharOnFoot(PLAYER_PED) then soltar(); return false end
        local px, py, pz = getCharCoordinates(PLAYER_PED)
        if getDistanceBetweenCoords3d(px,py,pz,x,y,z) <= dist_ok then
            soltar(); wait(40); return true
        end
        setCharHeading(PLAYER_PED, heading(x, y))
        kdown(VK.W)
        pcall(function() setGameKeyState(1, 255) end)
        if not first then
            if math.abs(px-lx)<0.04 and math.abs(py-ly)<0.04 then stk=stk+1 else stk=0 end
        end
        first, lx, ly = false, px, py
        if stk >= C.stuck then
            soltar(); wait(10)
            setCharHeading(PLAYER_PED, getCharHeading(PLAYER_PED)+35)
            wait(70); stk=0
        end
        wait(35)
    end
    soltar()
    return false
end

local function ir_caixa(id)
    local ok, x, y, z = achar_caixa(id)
    if not ok then
        set_status("Caixa " .. tostring(id) .. " nao encontrada")
        return false
    end
    local px, py, pz = getCharCoordinates(PLAYER_PED)
    if getDistanceBetweenCoords3d(px,py,pz,x,y,z) > C.dist then
        set_status("Indo a caixa " .. id)
        if not andar(x,y,z,C.dist) then
            set_status("Nao chegou na caixa " .. id)
            return false
        end
    end
    return true
end

local function wait_open(ms)
    local t = now()
    while now()-t < ms do
        if S.parar then return false end
        if sampIsDialogActive() then wait(C.after_open); return true end
        wait(10)
    end
    return sampIsDialogActive()
end

local function wait_close(ms)
    local t = now()
    while now()-t < ms do
        if not sampIsDialogActive() then wait(20); return true end
        wait(10)
    end
    return not sampIsDialogActive()
end

local function list_n()
    local ok, c = pcall(sampGetListboxItemsCount)
    return (ok and c) or 0
end

local function list_i(i)
    local ok, t = pcall(sampGetListboxItemText, i)
    return (ok and t) or ""
end

local function find_list(name)
    if not sampIsDialogActive() then return -1 end
    name = name:upper()
    for i = 0, list_n()-1 do
        local t = list_i(i)
        if t ~= "" and t:upper():find(name, 1, true) then return i end
    end
    return -1
end

local function vazio_txt(t)
    if not t or t == "" then return true end
    t = t:gsub("~%w~",""):gsub("%s+"," "):upper()
    if t == "" then return true end
    if t:find("VAZIO") or t:find("EMPTY") or t:find("NENHUM") or t:find("LIVRE") then return true end
    if t:find("%-") then return true end
    if t:match("^%d+$") then return true end
    return false
end

local function slot_vazio_lista()
    for i = 0, list_n()-1 do
        if vazio_txt(list_i(i)) then return i end
    end
    return -1
end

local function sel(i)
    if i < 0 then return false end
    pcall(function() sampSetCurrentDialogListItem(i) end)
    wait(25)
    key(VK.ENTER, C.delay)
    return true
end

local function fechar()
    if not sampIsDialogActive() then return end
    pcall(function() sampCloseCurrentDialogWithButton(0) end)
    wait(25)
    if sampIsDialogActive() then key(VK.ESC, 20) end
end

local function checar_id_dialog(id)
    if not sampIsDialogActive() or not id or id == 0 then return nil end
    local raw = ""
    local ok, txt = pcall(sampGetCurrentDialogText)
    if ok and type(txt)=="string" then raw = txt end
    if sampGetCurrentDialogCaption then
        local ok2, cap = pcall(sampGetCurrentDialogCaption)
        if ok2 and type(cap)=="string" then raw = cap.."\n"..raw end
    end
    if raw == "" then return nil end
    local limpo = raw:gsub("%d+%s*/%s*%d+",""):gsub("%(%d+%)",""):gsub("~%w~","")
    local id_str = tostring(id)
    if limpo:find(id_str, 1, true) then return true end
    local outro = limpo:match("^%s*(%d+)%s*[%.:%-]")
        or limpo:upper():match("CAIXA[^%d]*(%d+)")
    if outro and outro ~= id_str then return false, outro end
    return nil
end

local function press_n()
    ffi.C.keybd_event(VK.N, 0, 0, 0)
    wait(40)
    ffi.C.keybd_event(VK.N, 0, UP, 0)
    wait(30)
    if not sampIsDialogActive() then
        wait(50)
        ffi.C.keybd_event(VK.N, 0, 0, 0)
        wait(60)
        ffi.C.keybd_event(VK.N, 0, UP, 0)
    end
end

local function abrir_menu_n()
    if sampIsDialogActive() then fechar(); wait_close(C.close_ms) end
    wait(80)
    press_n()
    if not wait_open(C.open_ms) then
        wait(80); press_n()
        if not wait_open(C.open_ms) then return false end
    end
    wait(C.after_open)
    return true
end

local function abrir_portamalas()
    if not abrir_menu_n() then
        set_status("Menu N nao abriu")
        return false
    end
    local idx = find_list("PORTAMALAS")
    if idx < 0 then idx = find_list("PORTA-MALAS") end
    if idx < 0 then idx = find_list("PORTA MALAS") end
    if idx < 0 then
        fechar(); wait_close(C.close_ms)
        set_status("Opcao Portamalas nao achada")
        return false
    end
    pcall(function() sampSetCurrentDialogListItem(idx) end)
    wait(25)
    key(VK.ENTER, C.delay)
    if not wait_open(900) then
        set_status("Portamalas nao abriu")
        return false
    end
    wait(C.after_open)
    return true
end

-------------------------------------------------
-- COFRE: digita "NUM pegar/por QTD"
-------------------------------------------------
local function numero_cofre(item)
    local custom = tonumber(ffi.string(buf_cofre_num))
    if custom and custom > 0 then return custom end
    item = item:upper()
    if item:find("M4") then return COFRE_NUM.M4 end
    if item:find("DESERT") or item:find("DEAGLE") then return COFRE_NUM.DESERT end
    return COFRE_NUM.M4
end

local function enviar_input_dialog(texto)
    if not sampIsDialogActive() then return false end
    pcall(function()
        if sampSetCurrentDialogEditboxText then
            sampSetCurrentDialogEditboxText(texto)
        end
    end)
    wait(40)
    pcall(function()
        local id = -1
        if sampGetCurrentDialogId then id = sampGetCurrentDialogId() end
        if sampSendDialogResponse and id and id >= 0 then
            sampSendDialogResponse(id, 1, 0, texto)
            return
        end
        if sampCloseCurrentDialogWithButton then
            sampCloseCurrentDialogWithButton(1)
        end
    end)
    wait(80)
    wait_close(C.close_ms)
    return true
end

local function abrir_cofre()
    -- se o dialog ja esta aberto, NAO manda /cofre de novo
    if sampIsDialogActive() then
        wait(C.after_open)
        return true
    end
    set_status("/cofre")
    sampSendChat("/cofre")
    wait(150)
    if not wait_open(C.open_ms) then
        set_status("Dialog /cofre nao abriu")
        return false
    end
    wait(C.after_open)
    return true
end

local function cofre_cmd(item, acao, qtd)
    qtd = qtd or 1
    local num = numero_cofre(item)
    local txt = string.format("%d %s %d", num, acao, qtd)

    for tentativa = 1, C.cofre_retry do
        if S.parar then return false end
        set_status(string.format("Cofre: %s (%d/%d)", txt, tentativa, C.cofre_retry))

        if sampIsDialogActive() then
            fechar()
            wait_close(C.close_ms)
        end

        if not abrir_cofre() then
            wait(200)
        else
            enviar_input_dialog(txt)
            wait(120)
            if sampIsDialogActive() then
                fechar()
                wait_close(C.close_ms)
            end
            -- confirma no chat; se nao confirmou, repete
            if esperar_confirmacao_cofre() then
                return true
            end
            set_status("Cofre: repetindo...")
            wait(300)
        end
    end
    set_status("Cofre: falhou apos tentativas")
    return false
end



-------------------------------------------------
-- CAIXA (F + ID)
-------------------------------------------------
local function abrir_caixa(id)
    if sampIsDialogActive() then
        fechar()
        wait_close(C.close_ms)
    end
    if not id or id == 0 then
        set_status("ID da caixa obrigatorio")
        return false
    end
    if not ir_caixa(id) then return false end
    wait(30)
    set_status("Tecla F (caixa)")
    key(VK.F, C.delay)
    if not wait_open(C.open_ms) then
        set_status("Dialog da caixa nao abriu")
        return false
    end
    local ok_id, outro = checar_id_dialog(id)
    if ok_id == false then
        fechar()
        wait_close(C.close_ms)
        set_status("Caixa errada (achou " .. tostring(outro) .. ")")
        return false
    end
    return true
end

local function ir_itens()
    local it = find_list("ITENS")
    if it >= 0 then
        sel(it)
    else
        local ok, d = pcall(sampGetCurrentDialogText)
        if ok and d and d:upper():find("ITENS") then
            key(VK.ENTER, C.delay)
        else
            return sampIsDialogActive()
        end
    end
    if not wait_open(C.open_ms) then
        return sampIsDialogActive()
    end
    wait(30)
    return true
end

local function nome_por_tipo(tipo, buf)
    if tipo == 1 then return "M4" end
    if tipo == 2 then return "DESERT" end
    local n = ffi.string(buf)
    if n == "" then return "M4" end
    return n:upper()
end

local function linha_tem_item(texto, item)
    if not texto or texto == "" then return false end
    local u = texto:upper()
    if vazio_txt(texto) then return false end
    if u:find(item, 1, true) then return true end
    if item:find("DESERT") and (u:find("DEAGLE") or u:find("DESERT")) then return true end
    return false
end

local function tirar_indice(idx)
    if idx < 0 then return false end
    sel(idx)
    wait(50)
    if sampIsDialogActive() then key(VK.ENTER, C.delay); wait(40) end
    if sampIsDialogActive() then fechar() end
    wait_close(C.close_ms)
    return true
end

local function achar_slot_pm_vazio()
    if not sampIsDialogActive() then return -1 end
    for i = 0, list_n()-1 do
        local t = list_i(i)
        if t and t ~= "" then
            local u = t:upper()
            if not (u:find("FECHAR") or u:find("PESSOAS") or u:find("MATERIAIS")) then
                if u:find("SLOT") and (u:find("NENHUM") or u:find("VAZIO") or u:find("%(0%)")) then
                    return i
                end
            end
        end
    end
    return -1
end

local function achar_item_pm(item)
    if not sampIsDialogActive() then return -1 end
    for i = 0, list_n()-1 do
        local t = list_i(i)
        if t and t ~= "" then
            local u = t:upper()
            if not (u:find("FECHAR") or u:find("PESSOAS") or u:find("MATERIAIS")) then
                if linha_tem_item(t, item) then return i end
            end
        end
    end
    return -1
end

local function fechar_pm()
    if not sampIsDialogActive() then return end
    local idx = find_list("FECHAR")
    if idx >= 0 then
        pcall(function() sampSetCurrentDialogListItem(idx) end)
        wait(15); key(VK.ENTER, C.delay); wait(30)
    end
    if sampIsDialogActive() then fechar() end
    wait_close(C.close_ms)
end

local function tirar_item(id, tipo, item)
    set_status("Tirando de " .. nome_tipo(tipo))

    if tipo == 1 then
        return cofre_cmd(item, "pegar", 1)
    end

    if tipo == 2 then
        if not abrir_portamalas() then return false end
        local idx = achar_item_pm(item)
        if idx < 0 then
            fechar_pm()
            set_status("Item nao encontrado no PM")
            return false
        end
        pcall(function() sampSetCurrentDialogListItem(idx) end)
        wait(25)
        key(VK.ENTER, C.delay)
        wait(50)
        if sampIsDialogActive() then key(VK.ENTER, C.delay); wait(40) end
        if sampIsDialogActive() then fechar_pm() end
        wait_close(C.close_ms)
        return true
    end

    if not abrir_caixa(id) then return false end
    if not ir_itens() then fechar(); return false end
    local idx = -1
    for i = 0, list_n()-1 do
        if linha_tem_item(list_i(i), item) then idx = i; break end
    end
    if idx < 0 then
        fechar(); wait_close(C.close_ms)
        set_status("Item nao encontrado")
        return false
    end
    return tirar_indice(idx)
end

local function guardar_item(id, tipo, item)
    set_status("Guardando em " .. nome_tipo(tipo))

    if tipo == 1 then
        return cofre_cmd(item or "M4", "por", 1)
    end

    if tipo == 2 then
        if not abrir_portamalas() then return false end
        local slot = achar_slot_pm_vazio()
        if slot < 0 then
            if find_list("SLOT") >= 0 then
                set_status("Portamalas CHEIO")
                fechar_pm()
                return false
            end
            set_status("Slot PM nao achado")
            fechar_pm()
            return false
        end
        pcall(function() sampSetCurrentDialogListItem(slot) end)
        wait(25)
        key(VK.ENTER, C.delay)
        wait(40)
        if sampIsDialogActive() then key(VK.ENTER, C.delay) end
        if sampIsDialogActive() then fechar_pm() end
        wait_close(C.close_ms)
        return true
    end

    if not abrir_caixa(id) then return false end
    if not ir_itens() then fechar(); return false end
    local sv = slot_vazio_lista()
    if sv < 0 then
        fechar(); wait_close(C.close_ms)
        set_status("Destino CHEIO")
        return false
    end
    sel(sv)
    wait(50)
    if sampIsDialogActive() then key(VK.ENTER, C.delay); wait(40) end
    if sampIsDialogActive() then fechar() end
    wait_close(C.close_ms)
    return true
end

-------------------------------------------------
-- ORGANIZAR (so caixa + ID)
-------------------------------------------------
local function escanear_lista(item)
    local armas, vazios = {}, {}
    for i = 0, list_n()-1 do
        local t = list_i(i)
        if vazio_txt(t) then table.insert(vazios, i)
        elseif linha_tem_item(t, item) then table.insert(armas, i) end
    end
    return armas, vazios
end

local function ja_organizado(armas)
    if #armas <= 1 then return true end
    table.sort(armas)
    for i = 2, #armas do
        if armas[i] ~= armas[i-1] + 1 then return false end
    end
    return true
end

local function organizar()
    if S.rodando then return end
    S.id_org = tonumber(ffi.string(buf_org)) or S.id_org
    if S.id_org == 0 then
        sampAddChatMessage("{FF0000}[Organizar] {FFFFFF}ID da caixa obrigatorio.", -1)
        return
    end
    local item = nome_por_tipo(S.item_org, buf_org_item)
    S.rodando = true
    S.parar = false
    S.feita = 0
    S.qtd = 0
    sampAddChatMessage(string.format("{00BFFF}[Organizar] {FFFFFF}Caixa %d | %s", S.id_org, item), -1)
    set_status("Organizando...")
    local movimentos = 0
    for pass = 1, C.org_max do
        if S.parar then break end
        set_status("Lendo ("..pass..")")
        if not abrir_caixa(S.id_org) then break end
        if not ir_itens() then fechar(); break end
        local armas, vazios = escanear_lista(item)
        S.qtd = #armas
        if #armas == 0 then
            fechar(); wait_close(C.close_ms)
            set_status("Nenhuma "..item); break
        end
        if ja_organizado(armas) then
            fechar(); wait_close(C.close_ms)
            set_status("Ja organizado ("..#armas.."x)"); break
        end
        table.sort(armas)
        local alvo = armas[#armas]
        local destino = nil
        for _, v in ipairs(vazios) do
            if v < alvo then destino = v; break end
        end
        if not destino then
            if #vazios > 0 and vazios[1] < armas[1] then
                destino = vazios[1]; alvo = armas[1]
            else
                fechar(); wait_close(C.close_ms)
                set_status("Sem slot vazio"); break
            end
        end
        set_status(string.format("Movendo %d -> %d", alvo, destino))
        if not tirar_indice(alvo) then set_status("Falha ao tirar"); break end
        wait(100)
        if not guardar_item(S.id_org, 3, item) then set_status("Falha ao guardar"); break end
        movimentos = movimentos + 1
        S.feita = movimentos
        wait(100)
    end
    soltar()
    if sampIsDialogActive() then fechar(); wait_close(C.close_ms) end
    S.rodando = false
    S.parar = false
    if S.status == "Organizando..." then set_status("Organizado ("..S.feita.." mov)") end
    sampAddChatMessage("{00FF00}[Organizar] {FFFFFF}"..S.status, -1)
end

-------------------------------------------------
-- TRANSFER
-------------------------------------------------
local function transferir()
    if S.rodando then return end
    S.id_origem = tonumber(ffi.string(buf_ori)) or S.id_origem
    S.id_destino = tonumber(ffi.string(buf_des)) or S.id_destino

    if S.orig_tipo == 3 and S.id_origem == 0 then
        sampAddChatMessage("{FF0000}[Transfer] {FFFFFF}ID da caixa ORIGEM obrigatorio.", -1)
        return
    end
    if S.dest_tipo == 3 and S.id_destino == 0 then
        sampAddChatMessage("{FF0000}[Transfer] {FFFFFF}ID da caixa DESTINO obrigatorio.", -1)
        return
    end
    if S.orig_tipo == 3 and S.dest_tipo == 3 and S.id_origem == S.id_destino then
        sampAddChatMessage("{FF0000}[Transfer] {FFFFFF}Origem e destino iguais.", -1)
        return
    end

    local qtd = tonumber(ffi.string(buf_qtd)) or 1
    if qtd < 1 then qtd = 1 end
    if qtd > 40 then qtd = 40 end
    S.qtd = qtd
    S.feita = 0
    S.rodando = true
    S.parar = false

    local item = nome_por_tipo(S.item_tipo, buf_item)
    local o = nome_tipo(S.orig_tipo) .. (S.orig_tipo==3 and (" "..tostring(S.id_origem)) or "")
    local d = nome_tipo(S.dest_tipo) .. (S.dest_tipo==3 and (" "..tostring(S.id_destino)) or "")
    sampAddChatMessage(string.format("{00BFFF}[Transfer] {FFFFFF}%dx %s | %s -> %s", qtd, item, o, d), -1)

    for i = 1, qtd do
        if S.parar then set_status("Parado"); break end

        set_status(string.format("Tirando %d/%d", i, qtd))
        -- cofre_cmd ja confirma no chat e repete se falhar
        if not tirar_item(S.id_origem, S.orig_tipo, item) then
            sampAddChatMessage("{FF0000}[Transfer] {FFFFFF}Parou: "..S.status, -1)
            break
        end
        if S.orig_tipo ~= 1 then wait(150) end

        if S.parar then break end

        set_status(string.format("Guardando %d/%d", i, qtd))
        if not guardar_item(S.id_destino, S.dest_tipo, item) then
            sampAddChatMessage("{FF0000}[Transfer] {FFFFFF}Parou: "..S.status, -1)
            break
        end
        if S.dest_tipo ~= 1 then wait(150) end

        S.feita = S.feita + 1
    end


    soltar()
    if sampIsDialogActive() then fechar(); wait_close(C.close_ms) end
    S.rodando = false
    S.parar = false
    set_status("Concluido "..S.feita.."/"..S.qtd)
    sampAddChatMessage("{00FF00}[Transfer] {FFFFFF}"..S.status, -1)
end

-------------------------------------------------
-- UI
-------------------------------------------------
local function tema()
    local st = imgui.GetStyle()
    local c = st.Colors
    st.WindowRounding, st.FrameRounding, st.WindowBorderSize = 8, 5, 1
    st.ItemSpacing = imgui.ImVec2(8, 6)
    c[imgui.Col.WindowBg] = imgui.ImVec4(0.06, 0.09, 0.16, 0.97)
    c[imgui.Col.TitleBg] = imgui.ImVec4(0.09, 0.14, 0.26, 1)
    c[imgui.Col.TitleBgActive] = imgui.ImVec4(0.12, 0.20, 0.36, 1)
    c[imgui.Col.Button] = imgui.ImVec4(0.14, 0.28, 0.52, 1)
    c[imgui.Col.ButtonHovered] = imgui.ImVec4(0.20, 0.40, 0.70, 1)
    c[imgui.Col.ButtonActive] = imgui.ImVec4(0.10, 0.48, 0.80, 1)
    c[imgui.Col.Text] = imgui.ImVec4(0.93, 0.95, 1.00, 1)
    c[imgui.Col.FrameBg] = imgui.ImVec4(0.11, 0.16, 0.28, 1)
    c[imgui.Col.Border] = imgui.ImVec4(0.22, 0.38, 0.62, 0.55)
    c[imgui.Col.Separator] = imgui.ImVec4(0.22, 0.38, 0.62, 0.40)
end

local function btn_sel(label, ativo, id)
    local t = (ativo and ("[ "..label.." ]") or label).."##"..id
    if ativo then
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.12, 0.45, 0.28, 1))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.16, 0.55, 0.35, 1))
    end
    local click = imgui.Button(t)
    if ativo then imgui.PopStyleColor(2) end
    return click
end

imgui.OnFrame(function() return S.menu end, function()
    tema()
    imgui.SetNextWindowPos(S.pos, imgui.Cond.FirstUseEver)
    imgui.SetNextWindowSize(imgui.ImVec2(420, 700), imgui.Cond.FirstUseEver)
    imgui.Begin("AUTO TRANSFER", nil, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize)

    imgui.TextColored(imgui.ImVec4(0.50, 0.62, 0.85, 0.85), "Criador: vitorvtx")
    imgui.Separator(); imgui.Spacing()

    imgui.TextColored(imgui.ImVec4(0.4, 0.85, 1.0, 1), "TRANSFERIR")
    imgui.Spacing()

    imgui.Text("ORIGEM")
    if btn_sel("COFRE", S.orig_tipo==1, "o1") then S.orig_tipo=1 end
    imgui.SameLine()
    if btn_sel("PORTAMALAS", S.orig_tipo==2, "o2") then S.orig_tipo=2 end
    imgui.SameLine()
    if btn_sel("CAIXA", S.orig_tipo==3, "o3") then S.orig_tipo=3 end

    if S.orig_tipo == 1 then
        imgui.TextColored(imgui.ImVec4(0.7, 0.85, 0.5, 1), "Abre: /cofre | confirma no chat")
    elseif S.orig_tipo == 2 then
        imgui.TextColored(imgui.ImVec4(0.7, 0.85, 0.5, 1), "Abre: N (sem ID)")
    else
        imgui.TextColored(imgui.ImVec4(0.7, 0.85, 0.5, 1), "Abre: F (precisa ID)")
        imgui.Text("ID da caixa ORIGEM")
        imgui.PushItemWidth(110); imgui.InputText("##ori", buf_ori, 12); imgui.PopItemWidth()
    end

    imgui.Spacing()
    imgui.Text("DESTINO")
    if btn_sel("COFRE", S.dest_tipo==1, "d1") then S.dest_tipo=1 end
    imgui.SameLine()
    if btn_sel("PORTAMALAS", S.dest_tipo==2, "d2") then S.dest_tipo=2 end
    imgui.SameLine()
    if btn_sel("CAIXA", S.dest_tipo==3, "d3") then S.dest_tipo=3 end

    if S.dest_tipo == 1 then
        imgui.TextColored(imgui.ImVec4(0.7, 0.85, 0.5, 1), "Abre: /cofre | confirma no chat")

    elseif S.dest_tipo == 2 then
        imgui.TextColored(imgui.ImVec4(0.7, 0.85, 0.5, 1), "Abre: N (sem ID)")
    else
        imgui.TextColored(imgui.ImVec4(0.7, 0.85, 0.5, 1), "Abre: F (precisa ID)")
        imgui.Text("ID da caixa DESTINO")
        imgui.PushItemWidth(110); imgui.InputText("##des", buf_des, 12); imgui.PopItemWidth()
    end

    if imgui.Button("Aplicar##tr", imgui.ImVec2(100, 0)) then
        S.id_origem = tonumber(ffi.string(buf_ori)) or 0
        S.id_destino = tonumber(ffi.string(buf_des)) or 0
        sampAddChatMessage(string.format("{00BFFF}[Transfer] {FFFFFF}%s -> %s",
            nome_tipo(S.orig_tipo), nome_tipo(S.dest_tipo)), -1)
    end

    imgui.Text("Item")
    if btn_sel("M4", S.item_tipo==1, "i1") then S.item_tipo=1 end
    imgui.SameLine()
    if btn_sel("Desert", S.item_tipo==2, "i2") then S.item_tipo=2 end
    imgui.SameLine()
    if btn_sel("Custom", S.item_tipo==3, "i3") then S.item_tipo=3 end
    if S.item_tipo == 3 then
        imgui.PushItemWidth(160); imgui.InputText("##item", buf_item, 32); imgui.PopItemWidth()
    end

    imgui.Text("Num cofre (opcional, padrao M4=14 Desert=6)")
    imgui.PushItemWidth(70); imgui.InputText("##cnum", buf_cofre_num, 8); imgui.PopItemWidth()

    imgui.Text("Quantidade")
    imgui.PushItemWidth(70); imgui.InputText("##qtd", buf_qtd, 8); imgui.PopItemWidth()

    if not S.rodando then
        if imgui.Button("INICIAR TRANSFER", imgui.ImVec2(160, 26)) then
            lua_thread.create(transferir)
        end
    end

    imgui.Spacing(); imgui.Separator(); imgui.Spacing()

    imgui.TextColored(imgui.ImVec4(1.0, 0.75, 0.35, 1), "ORGANIZAR CAIXA (so com ID)")
    imgui.Text("ID da caixa")
    imgui.PushItemWidth(110); imgui.InputText("##orgid", buf_org, 12); imgui.PopItemWidth()
    imgui.Text("Arma")
    if btn_sel("M4", S.item_org==1, "io1") then S.item_org=1 end
    imgui.SameLine()
    if btn_sel("Desert", S.item_org==2, "io2") then S.item_org=2 end
    imgui.SameLine()
    if btn_sel("Custom", S.item_org==3, "io3") then S.item_org=3 end
    if S.item_org == 3 then
        imgui.PushItemWidth(160); imgui.InputText("##orgitem", buf_org_item, 32); imgui.PopItemWidth()
    end
    if imgui.Button("Aplicar ID organizar", imgui.ImVec2(160, 0)) then
        S.id_org = tonumber(ffi.string(buf_org)) or 0
        sampAddChatMessage("{00BFFF}[Organizar] {FFFFFF}Caixa "..tostring(S.id_org), -1)
    end

    if not S.rodando then
        if imgui.Button("ORGANIZAR", imgui.ImVec2(140, 26)) then
            lua_thread.create(organizar)
        end
    else
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.55, 0.15, 0.15, 1))
        if imgui.Button("PARAR", imgui.ImVec2(100, 26)) then
            S.parar = true
            set_status("Parando...")
        end
        imgui.PopStyleColor()
    end

    imgui.Spacing(); imgui.Separator(); imgui.Spacing()
    imgui.TextColored(imgui.ImVec4(1.0, 0.85, 0.30, 1), "Status: "..S.status)
    imgui.Text(string.format("Progresso: %d / %d", S.feita, S.qtd))
    if S.rodando then
        imgui.TextColored(imgui.ImVec4(0.30, 0.90, 0.50, 1), "Em execucao...")
    end
    imgui.Spacing()
    imgui.TextColored(imgui.ImVec4(0.40, 0.50, 0.70, 0.65), "COFRE=confirma/repete | PM=N | CAIXA=F+ID")

    imgui.TextColored(imgui.ImVec4(0.55, 0.60, 0.70, 0.7), "Cofre M4=14 | Desert=6")
    S.pos = imgui.GetWindowPos()
    imgui.End()
end)

function main()
    while not isSampAvailable() do wait(100) end
    wait(400)
    sampRegisterChatCommand("transfer", function()
        S.menu = not S.menu
        sampAddChatMessage(
            S.menu and "{00FF00}[Transfer] {FFFFFF}Menu aberto" or "{FFAA00}[Transfer] {FFFFFF}Menu fechado",
            -1
        )
    end)
    sampAddChatMessage("{00BFFF}[Transfer] {FFFFFF}Carregado v3.7 | Cofre: confirma e repete", -1)


    while true do wait(100) end
end
