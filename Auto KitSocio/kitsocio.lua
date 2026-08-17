--[[
    AUTO KITSOCIO BRASIL ROLEPLAY
    Criador: vitorvtx | MoonLoader 0.26 + mimgui
]]
script_name("Auto KitSocio BRP")
script_author("vitorvtx")
script_version("9.4")



require "lib.moonloader"
local imgui, sampev, ffi = require "mimgui", require "lib.samp.events", require "ffi"

local C = {
    tecla = 0x2D,
    t_kit = 120000, t_status = 600000,
    delay = 150, int_e = 3500, cd_guardar = 7000, timeout = 20000, limite = 80,
    dist = 1.6, walk_ms = 10000, stuck = 25,
}

local S = {
    menu=false, caixa=false, comer=false, dormir=false,
    m4=true, desert=true, id_m4=0, id_des=0,
    busy=false, busy_t=0, next_kit=0, next_e=0, next_st=0,
    n_m4=0, n_des=0,
    fome=-1, sede=-1, sono=-1,
    fill_f=false, fill_s=false, fill_o=false, em_st=false,
    pos=imgui.ImVec2(80,80),
}
local buf_m4, buf_des = imgui.new.char[12](""), imgui.new.char[12]("")

ffi.cdef[[void keybd_event(unsigned char,unsigned char,unsigned long,unsigned long);]]
local UP = 0x0002
local VK = {E=0x45,F=0x46,W=0x57,ENTER=0x0D,DOWN=0x28,ESC=0x1B}

local function now() return os.clock()*1000 end
local function tstr(ms)
    local t=math.max(0,math.floor(ms/1000)); return string.format("%02d:%02d",math.floor(t/60),t%60)
end
local function key(vk,d)
    ffi.C.keybd_event(vk,0,0,0); wait(18); ffi.C.keybd_event(vk,0,UP,0); wait(d or C.delay)
end
local function kdown(vk) ffi.C.keybd_event(vk,0,0,0) end
local function kup(vk) ffi.C.keybd_event(vk,0,UP,0) end
local function soltar()
    kup(VK.W)
    pcall(function()
        setGameKeyState(1,0) setGameKeyState(2,0) setGameKeyState(3,0) setGameKeyState(4,0)
    end)
end

-------------------------------------------------
-- TEXTDRAW (FOME / SEDE / SONO)
-------------------------------------------------
local function parse(t)
    if not t or type(t)~="string" then return end
    t=t:gsub("~%w~",""):upper()
    local a=t:match("FOME:%s*(%d+)") or t:match("FOME%s*(%d+)")
    local b=t:match("SEDE:%s*(%d+)") or t:match("SEDE%s*(%d+)")
    local c=t:match("SONO:%s*(%d+)") or t:match("SONO%s*(%d+)")
    if a then S.fome=tonumber(a) end
    if b then S.sede=tonumber(b) end
    if c then S.sono=tonumber(c) end
end
function sampev.onShowTextDraw(_,d) if d and d.text then parse(d.text) end end
function sampev.onTextDrawSetString(_,t) parse(t) end
local function ler()
    for i=0,2304 do
        if sampTextdrawIsExists(i) then
            local t=sampTextdrawGetString(i)
            if t then parse(t) end
        end
    end
end

-------------------------------------------------
-- 3D CAIXA
-------------------------------------------------
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
        local existe = false
        if sampIs3dTextDefined then
            local ok, r = pcall(sampIs3dTextDefined, i)
            existe = ok and r
        end
        if existe then
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
            if text and text:upper():find(needle,1,true) and x and y and z then
                return true, x, y, z
            end
        end
    end
    return false, 0, 0, 0
end

-------------------------------------------------
-- WALK
-------------------------------------------------
local function heading(tx, ty)
    local px, py = getCharCoordinates(PLAYER_PED)
    local ok, h = pcall(function() return getHeadingFromVector2d(tx-px, ty-py) end)
    if ok and h then return h end
    return -math.deg(math.atan2(ty-py, tx-px)) + 90
end

local function andar(x, y, z)
    local fim, lx, ly, stk, first = now()+C.walk_ms, 0, 0, 0, true
    soltar(); wait(25)
    while now() < fim do
        if not isCharOnFoot(PLAYER_PED) then soltar(); return false end
        local px, py, pz = getCharCoordinates(PLAYER_PED)
        if getDistanceBetweenCoords3d(px,py,pz,x,y,z) <= C.dist then
            soltar(); wait(60); return true
        end
        setCharHeading(PLAYER_PED, heading(x,y))
        kdown(VK.W)
        pcall(function() setGameKeyState(1,255) end)
        if not first then
            if math.abs(px-lx)<0.04 and math.abs(py-ly)<0.04 then stk=stk+1 else stk=0 end
        end
        first, lx, ly = false, px, py
        if stk >= C.stuck then
            soltar(); wait(20)
            setCharHeading(PLAYER_PED, getCharHeading(PLAYER_PED)+35)
            wait(100); stk=0
        end
        wait(40)
    end
    soltar()
    return false
end

-------------------------------------------------
-- DIALOG
-------------------------------------------------
local function wait_open(ms)
    local t=now()
    while now()-t<ms do
        if sampIsDialogActive() then wait(50); return true end
        wait(12)
    end
    return sampIsDialogActive()
end
local function wait_close(ms)
    local t=now()
    while now()-t<ms do
        if not sampIsDialogActive() then wait(30); return true end
        wait(12)
    end
    return not sampIsDialogActive()
end
local function list_n()
    local ok,c=pcall(sampGetListboxItemsCount)
    return (ok and c) or 0
end
local function list_i(i)
    local ok,t=pcall(sampGetListboxItemText,i)
    return (ok and t) or ""
end
local function find_list(name)
    if not sampIsDialogActive() then return -1 end
    name=name:upper()
    for i=0,list_n()-1 do
        local t=list_i(i)
        if t~="" and t:upper():find(name,1,true) then return i end
    end
    return -1
end
local function vazio(t)
    if not t or t=="" then return true end
    t=t:gsub("~%w~",""):gsub("%s+"," "):upper()
    if t=="" or t:find("VAZIO") or t:find("EMPTY") or t:find("%-") or t:find("LIVRE") or t:find("NENHUM") then
        return true
    end
    return t:match("^%d+$")~=nil
end
local function slot_vazio()
    if not sampIsDialogActive() then return -1 end
    for i=0,list_n()-1 do if vazio(list_i(i)) then return i end end
    return -1
end
local function sel(i)
    if i<0 then return false end
    pcall(function() sampSetCurrentDialogListItem(i) end)
    wait(45); key(VK.ENTER,200); return true
end
local function fechar()
    if not sampIsDialogActive() then return end
    pcall(function() sampCloseCurrentDialogWithButton(0) end)
    wait(35)
    if sampIsDialogActive() then key(VK.ESC,20) end
end

local function dialog_e_caixa(id)
    if not sampIsDialogActive() then return nil end
    local raw = ""
    local ok, txt = pcall(sampGetCurrentDialogText)
    if ok and type(txt) == "string" then raw = raw .. "\n" .. txt end
    if sampGetCurrentDialogCaption then
        local ok2, cap = pcall(sampGetCurrentDialogCaption)
        if ok2 and type(cap) == "string" then raw = raw .. "\n" .. cap end
    end
    if sampGetDialogInfo then
        local ok3, a, b, c, d, e = pcall(sampGetDialogInfo)
        if ok3 then
            for _, v in ipairs({a, b, c, d, e}) do
                if type(v) == "string" then raw = raw .. "\n" .. v end
            end
        end
    end
    if raw == "" then return nil end
    local limpo = raw:gsub("%d+%s*/%s*%d+", ""):gsub("%(%d+%)", ""):gsub("~%w~", "")
    local id_str = tostring(id)
    if limpo:find(id_str, 1, true) then return true end
    local outro = limpo:match("CAIXA DE ITENS%s*(%d+)")
        or limpo:match("CAIXA%s+DE%s+ITENS%s*(%d+)")
        or limpo:match("^%s*(%d+)%s*[%.:%-]")
    if outro and outro ~= id_str then return false end
    return nil
end

-- /comer e /beber: espera dialog -> seta baixo -> enter -> enter
local function chat_comida(cmd)
    if sampIsDialogActive() then
        fechar()
        wait_close(800)
    end

    sampSendChat(cmd)
    wait(80)

    local vezes = 0
    while vezes < 10 do
        if not wait_open(1500) then
            return true
        end

        wait(40)

        local ok_txt, txt = pcall(sampGetCurrentDialogText)
        local u = (ok_txt and type(txt) == "string") and txt:upper() or ""
        if u:find("NAO TEM") or u:find("NÃO TEM") or u:find("VAZIA") or u:find("NENHUM")
            or u:find("SEM COMIDA") or u:find("SEM BEBIDA") or u:find("NAO POSSUI") then
            fechar()
            wait_close(600)
            return false
        end

        local count = list_n()
        if count <= 1 and (u:find("ERRO") or u:find("NAO")) then
            fechar()
            wait_close(600)
            return false
        end

        key(VK.DOWN, 35)
        pcall(function() sampSetCurrentDialogListItem(1) end)
        wait(25)
        key(VK.ENTER, 45)
        wait(30)
        key(VK.ENTER, 45)

        wait_close(1000)
        vezes = vezes + 1

        wait(120)
        local t = now()
        local reabriu = false
        while now() - t < 500 do
            if sampIsDialogActive() then
                reabriu = true
                break
            end
            wait(20)
        end
        if not reabriu then
            return true
        end
    end

    if sampIsDialogActive() then
        fechar()
        wait_close(500)
    end
    return true
end

-- /dormir: UMA VEZ so
local function chat_dormir()
    if sampIsDialogActive() then
        fechar()
        wait_close(800)
    end
    sampSendChat("/dormir")
    wait(150)
end

local function desligar_comer(motivo)
    S.comer = false
    S.fill_f, S.fill_s = false, false
    sampAddChatMessage("{FF0000}[AutoKit] {FFFFFF}COMER/BEBER desativado: "..motivo, -1)
end

-------------------------------------------------
-- CAIXA
-------------------------------------------------
local function seq_local(id_esperado)
    if sampIsDialogActive() then fechar(); wait_close(700); wait(60) end

    key(VK.F, 180)
    if not wait_open(1100) then return false end

    local ok_id = dialog_e_caixa(id_esperado)
    if ok_id == false then
        fechar()
        wait_close(600)
        sampAddChatMessage("{FFAA00}[AutoKit] {FFFFFF}Caixa errada (nao e "..tostring(id_esperado)..").", -1)
        return false
    end

    local it = find_list("ITENS")
    if it >= 0 then
        sel(it)
    else
        local ok, d = pcall(sampGetCurrentDialogText)
        if not (ok and d and d:upper():find("ITENS")) then
            fechar()
            return false
        end
        key(VK.ENTER, 200)
    end

    if not wait_open(900) then return false end
    wait(60)

    local sv = slot_vazio()
    if sv < 0 then
        fechar(); wait_close(700)
        S.caixa, S.busy, S.busy_t, S.next_kit, S.next_e = false, false, 0, 0, 0
        sampAddChatMessage("{FF0000}[AutoKit] {FFFFFF}Caixa CHEIA. Desativada.", -1)
        return false
    end

    sel(sv)
    wait(80)
    if sampIsDialogActive() then key(VK.ENTER, 180); wait(60) end
    if sampIsDialogActive() then fechar() end
    wait_close(900)
    return true
end

local function guardar_em(id)
    if not id or id == 0 then
        sampAddChatMessage("{FF0000}[AutoKit] {FFFFFF}Defina o ID da caixa no menu.", -1)
        return false
    end

    local ok, x, y, z = achar_caixa(id)
    if not ok then
        sampAddChatMessage("{FF0000}[AutoKit] {FFFFFF}Caixa "..tostring(id).." nao encontrada.", -1)
        return false
    end

    local px, py, pz = getCharCoordinates(PLAYER_PED)
    if getDistanceBetweenCoords3d(px, py, pz, x, y, z) > C.dist then
        if not andar(x, y, z) then
            soltar()
            sampAddChatMessage("{FFAA00}[AutoKit] {FFFFFF}Nao chegou na caixa "..tostring(id), -1)
            return false
        end
    end

    wait(80)
    return seq_local(id)
end

local function tentar_guardar()
    if S.busy or not S.caixa or sampIsDialogActive() then return end
    S.busy, S.busy_t = true, now()
    key(VK.E, 300)
    wait(500)
    local arma = getCurrentCharWeapon(PLAYER_PED)
    local ok = false
    if arma == 31 and S.m4 then
        ok = guardar_em(S.id_m4)
        if ok then S.n_m4 = S.n_m4 + 1 end
    elseif arma == 24 and S.desert then
        ok = guardar_em(S.id_des)
        if ok then S.n_des = S.n_des + 1 end
    end
    soltar()
    S.busy, S.busy_t = false, 0
    if ok then S.next_e = now() + C.cd_guardar end
end

local function do_kit()
    sampSendChat("/kitsocio")
    S.next_kit = now() + C.t_kit
end

-------------------------------------------------
-- STATUS
-- Fome/Sede: abaixo de 80 -> enche ate 100
-- Sono: abaixo de 80 -> /dormir UMA vez so
-------------------------------------------------
local function ciclo_status()
    if S.em_st or S.busy then return end
    S.em_st, S.fill_f, S.fill_s, S.fill_o = true, false, false, false
    ler()

    if S.comer then
        if S.fome >= 0 and S.fome < C.limite then S.fill_f = true end
        if S.sede >= 0 and S.sede < C.limite then S.fill_s = true end
    end
    if S.dormir and S.sono >= 0 and S.sono < C.limite then
        S.fill_o = true
    end

    if not (S.fill_f or S.fill_s or S.fill_o) then
        S.em_st = false
        S.next_st = now() + C.t_status
        return
    end

    local falhou_comida, falhou_bebida = false, false

    if S.fill_o and S.dormir and not S.busy then
        S.busy, S.busy_t = true, now()
        chat_dormir()
        S.busy, S.busy_t = false, 0
        S.fill_o = false
        wait(200)
    end

    while S.comer and S.em_st and (S.fill_f or S.fill_s) do
        ler()
        if S.fill_f and S.fome >= 100 then S.fill_f = false end
        if S.fill_s and S.sede >= 100 then S.fill_s = false end
        if not (S.fill_f or S.fill_s) then break end

        if not S.busy then
            if S.fill_f and S.fome >= 0 and S.fome < 100 then
                S.busy, S.busy_t = true, now()
                local ok = chat_comida("/comer")
                S.busy, S.busy_t = false, 0
                if not ok then falhou_comida = true; S.fill_f = false end
            elseif S.fill_s and S.sede >= 0 and S.sede < 100 then
                S.busy, S.busy_t = true, now()
                local ok = chat_comida("/beber")
                S.busy, S.busy_t = false, 0
                if not ok then falhou_bebida = true; S.fill_s = false end
            end
        end

        if falhou_comida and falhou_bebida then
            desligar_comer("sem comida e bebida na bolsa"); break
        end
        if falhou_comida and S.fome >= 0 and S.fome < 100 and not S.fill_s then
            desligar_comer("sem comida na bolsa"); break
        end
        if falhou_bebida and S.sede >= 0 and S.sede < 100 and not S.fill_f then
            desligar_comer("sem bebida na bolsa"); break
        end

        wait(80)
    end

    S.em_st = false
    S.next_st = now() + C.t_status
end

-------------------------------------------------
-- UI
-------------------------------------------------
local function tema()
    local st, c = imgui.GetStyle(), imgui.GetStyle().Colors
    st.WindowRounding, st.FrameRounding, st.WindowBorderSize = 7, 4, 1
    c[imgui.Col.WindowBg] = imgui.ImVec4(0.07, 0.10, 0.18, 0.96)
    c[imgui.Col.TitleBg] = imgui.ImVec4(0.10, 0.16, 0.28, 1)
    c[imgui.Col.TitleBgActive] = imgui.ImVec4(0.12, 0.20, 0.35, 1)
    c[imgui.Col.Button] = imgui.ImVec4(0.15, 0.28, 0.50, 1)
    c[imgui.Col.ButtonHovered] = imgui.ImVec4(0.20, 0.38, 0.65, 1)
    c[imgui.Col.ButtonActive] = imgui.ImVec4(0.12, 0.45, 0.75, 1)
    c[imgui.Col.Text] = imgui.ImVec4(0.92, 0.94, 1, 1)
    c[imgui.Col.Border] = imgui.ImVec4(0.20, 0.35, 0.60, 0.55)
    c[imgui.Col.FrameBg] = imgui.ImVec4(0.12, 0.18, 0.30, 1)
end
local function st(on)
    imgui.TextColored(on and imgui.ImVec4(0.2,0.9,0.4,1) or imgui.ImVec4(0.9,0.3,0.3,1),
        on and "LIGADO" or "DESLIGADO")
end

imgui.OnFrame(function() return S.menu end, function()
    tema()
    imgui.SetNextWindowPos(S.pos, imgui.Cond.FirstUseEver)
    imgui.SetNextWindowSize(imgui.ImVec2(370, 600), imgui.Cond.FirstUseEver)
    imgui.Begin("AUTO KITSOCIO BRASIL ROLEPLAY", nil, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize)
    imgui.TextColored(imgui.ImVec4(0.45, 0.55, 0.75, 0.75), "Criador: vitorvtx")
    imgui.Separator(); imgui.Spacing()

    imgui.Text("CAIXA DE ITENS"); st(S.caixa); imgui.SameLine(240)
    if imgui.Button(S.caixa and "Desativar##cx" or "Ativar##cx", imgui.ImVec2(100,0)) then
        S.caixa = not S.caixa
        if S.caixa then
            local t = now()
            if S.next_kit == 0 then S.next_kit = t + 3000 end
            if S.next_e == 0 then S.next_e = t + 1500 end
        else
            S.busy, S.next_kit, S.next_e = false, 0, 0
            soltar()
        end
    end
    imgui.Spacing()
    if imgui.Button(S.m4 and "M4: SIM" or "M4: NAO", imgui.ImVec2(80,0)) then S.m4 = not S.m4 end
    imgui.SameLine()
    if imgui.Button(S.desert and "Desert: SIM" or "Desert: NAO", imgui.ImVec2(100,0)) then S.desert = not S.desert end

    imgui.Text("ID Caixa M4:")
    imgui.PushItemWidth(90); imgui.InputText("##m4", buf_m4, 12); imgui.PopItemWidth()
    imgui.Text("ID Caixa Desert:")
    imgui.PushItemWidth(90); imgui.InputText("##des", buf_des, 12); imgui.PopItemWidth()
    if imgui.Button("Aplicar IDs", imgui.ImVec2(110,0)) then
        S.id_m4 = tonumber(ffi.string(buf_m4)) or 0
        S.id_des = tonumber(ffi.string(buf_des)) or 0
        sampAddChatMessage(string.format("{00BFFF}[AutoKit] {FFFFFF}M4=%d Desert=%d", S.id_m4, S.id_des), -1)
    end
    imgui.Text(string.format("Atual: M4=%s | Desert=%s",
        S.id_m4 > 0 and tostring(S.id_m4) or "---",
        S.id_des > 0 and tostring(S.id_des) or "---"))

    imgui.Spacing(); imgui.Separator(); imgui.Spacing()

    imgui.Text("COMER/BEBER AUTO"); st(S.comer); imgui.SameLine(240)
    if imgui.Button(S.comer and "Desativar##cb" or "Ativar##cb", imgui.ImVec2(100,0)) then
        S.comer = not S.comer
        if S.comer and S.next_st == 0 then S.next_st = now() + 2000 end
    end
    imgui.Text(string.format("Fome: %s | Sede: %s",
        S.fome >= 0 and S.fome.."%" or "?", S.sede >= 0 and S.sede.."%" or "?"))

    imgui.Spacing(); imgui.Separator(); imgui.Spacing()

    imgui.Text("DORMIR AUTO"); st(S.dormir); imgui.SameLine(240)
    if imgui.Button(S.dormir and "Desativar##dr" or "Ativar##dr", imgui.ImVec2(100,0)) then
        S.dormir = not S.dormir
        if S.dormir and S.next_st == 0 then S.next_st = now() + 2000 end
    end
    imgui.Text(string.format("Sono: %s  (1x se < %d%%)", S.sono >= 0 and S.sono.."%" or "?", C.limite))

    imgui.Spacing(); imgui.Separator(); imgui.Spacing()
    imgui.TextColored(imgui.ImVec4(0.3,0.9,0.5,1), "M4: "..S.n_m4)
    imgui.TextColored(imgui.ImVec4(0.9,0.7,0.2,1), "Desert: "..S.n_des)

    local t = now()
    if S.caixa and S.next_kit > 0 then imgui.Text("Kit: "..tstr(S.next_kit-t)) end
    if (S.comer or S.dormir) and S.next_st > 0 and not S.em_st then
        imgui.Text("Status: "..tstr(S.next_st-t))
    end
    if S.em_st then imgui.TextColored(imgui.ImVec4(1,0.8,0.2,1), "Enchendo...") end
    if S.busy then imgui.TextColored(imgui.ImVec4(1,0.8,0.2,1), "Executando...") end

    imgui.Spacing()
    if imgui.Button("Destravar", imgui.ImVec2(100,0)) then
        S.busy, S.busy_t, S.em_st = false, 0, false
        soltar()
    end
    imgui.TextColored(imgui.ImVec4(0.4,0.5,0.7,0.65), "Insert ou /autokit")
    S.pos = imgui.GetWindowPos()
    imgui.End()
end)

-------------------------------------------------
-- WORKER (unica thread com wait - evita crash coroutine)
-------------------------------------------------
local function worker()
    while true do
        wait(80)
        local ok, err = pcall(function()
            local t = now()

            if S.busy and S.busy_t > 0 and (t - S.busy_t) > C.timeout then
                S.busy, S.busy_t, S.em_st = false, 0, false
                soltar()
            end

            if S.caixa and not S.busy and not S.em_st then
                if S.next_kit > 0 and t >= S.next_kit then
                    do_kit()
                end
                if S.next_e > 0 and t >= S.next_e and not S.busy then
                    S.next_e = t + C.int_e
                    tentar_guardar()
                end
            end

            if (S.comer or S.dormir) and not S.em_st and not S.busy and S.next_st > 0 and t >= S.next_st then
                ciclo_status()
            end
        end)
        if not ok then
            S.busy, S.busy_t, S.em_st = false, 0, false
            soltar()
            print("[AutoKit] worker erro: " .. tostring(err))
            wait(500)
        end
    end
end


-------------------------------------------------
-- MAIN
-------------------------------------------------
function main()
    while not isSampAvailable() do wait(100) end
    wait(800)

    sampRegisterChatCommand("autokit", function()
        S.menu = not S.menu
        sampAddChatMessage(S.menu and "{00FF00}[AutoKit] ABERTO" or "{FF0000}[AutoKit] FECHADO", -1)
    end)

    sampRegisterChatCommand("scan3d", function()
        local n = 0
        for i = 0, 2048 do
            local okd, def = pcall(function()
                return sampIs3dTextDefined and sampIs3dTextDefined(i)
            end)
            if okd and def then
                local a = get_3d_info(i)
                if type(a) == "string" and a:upper():find("CAIXA") then
                    sampAddChatMessage(string.format("{AAAAAA}[%d] {FFFFFF}%s", i, a:sub(1,70)), -1)
                    n = n + 1
                end
            end
        end
        sampAddChatMessage("{00BFFF}[AutoKit] {FFFFFF}3D CAIXA: "..n, -1)
    end)

    sampAddChatMessage("{00BFFF}[Auto KitSocio] {FFFFFF}v9.4 carregado! INSERT / /autokit", -1)

    -- worker unico (todos os wait ficam aqui)
    lua_thread.create(worker)

    -- main so cuida do menu
    while true do
        wait(50)
        if wasKeyPressed(C.tecla) then S.menu = not S.menu end
    end
end


