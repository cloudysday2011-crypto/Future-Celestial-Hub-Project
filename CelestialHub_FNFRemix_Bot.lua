--[[
	Celestial Hub | FNF Remix Bot V1
	- Burbuja (textura de Celestial Hub) -> ventana con "FNF Bot" y "FNF REMIX KEYS ERROR LOG".
	- Envia teclado real (VirtualInputManager) aunque estes en celular:
	  Left = Z | Down = X | Up = Comma (,) | Right = Period (.)
	- Detecta las flechas leyendo la interfaz (ImageLabel/ImageButton) y calibra por geometria, sin nombres.
	- Cada tecla enviada se verifica con UserInputService; los fallos quedan en el log.
	VERSION EXPERIMENTAL: la deteccion de flechas no esta probada en el juego. Si falla, el log dice por que.
]]

if _G.CelestialFNF and type(_G.CelestialFNF.Destroy) == "function" then
	pcall(_G.CelestialFNF.Destroy)
end

local FNF = {Enabled = false, SpoofPC = false, LeadMs = 20, EnabledAt = 0, Page = "menu", Open = false, Running = true, LogDirty = true}
_G.CelestialFNF = FNF

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local lp = Players.LocalPlayer
local pg = lp:WaitForChild("PlayerGui")
local VIM
pcall(function() VIM = game:GetService("VirtualInputManager") end)

local T0 = os.clock()
local conns = {}
local function track(c) conns[#conns + 1] = c return c end

local BUBBLE_ID = "rbxassetid://118869628234830"
local C = {
	Dark = Color3.fromRGB(11, 10, 23), Purple = Color3.fromRGB(26, 21, 56), MoonBlue = Color3.fromRGB(155, 190, 255),
	Lilac = Color3.fromRGB(185, 166, 255), Silver = Color3.fromRGB(211, 213, 223), White = Color3.fromRGB(248, 248, 255),
	Green = Color3.fromRGB(93, 255, 157), Red = Color3.fromRGB(255, 107, 129), Button = Color3.fromRGB(14, 13, 29),
	Gray = Color3.fromRGB(145, 147, 160),
}

-- Orden de carriles = orden de izquierda a derecha en pantalla.
local LANES = {
	{Name = "Left", Key = Enum.KeyCode.Z, Label = "Z", VK = 0x5A},
	{Name = "Down", Key = Enum.KeyCode.X, Label = "X", VK = 0x58},
	{Name = "Up", Key = Enum.KeyCode.Comma, Label = ",", VK = 0xBC},
	{Name = "Right", Key = Enum.KeyCode.Period, Label = ".", VK = 0xBE},
}
local LANE_BY_KEY = {}
for _, lane in ipairs(LANES) do LANE_BY_KEY[lane.Key] = lane end

-- ============================ LOG ============================
local Log = {Lines = {}, Max = 300}
local lastLogAt = {}
local function addLog(kind, msg)
	local line = string.format("[%6.1f] %-6s %s", os.clock() - T0, kind, msg)
	local L = Log.Lines
	L[#L + 1] = line
	if #L > Log.Max then table.remove(L, 1) end
	FNF.LogDirty = true
end
local function logEvery(key, secs, kind, msg)
	local now = os.clock()
	if now - (lastLogAt[key] or -1e9) >= secs then
		lastLogAt[key] = now
		addLog(kind, msg)
	end
end

addLog("INFO", string.format("VIM=%s keypress=%s Teclado=%s Touch=%s", tostring(VIM ~= nil),
	tostring(typeof(keypress) == "function"), tostring(UIS.KeyboardEnabled), tostring(UIS.TouchEnabled)))

-- ============================ TECLAS ============================
local pendingDown = {}
local Keys = {Sent = 0, Confirmed = 0, Failures = 0, Streak = 0, Backend = "-"}

local function rawKey(down, kc, vk)
	if VIM then
		local ok = pcall(function() VIM:SendKeyEvent(down, kc, false, game) end)
		if ok then return true, "VIM" end
	end
	local fn = down and keypress or keyrelease
	if typeof(fn) == "function" and vk then
		local ok = pcall(fn, vk)
		if ok then return true, "keypress" end
	end
	return false, "ninguno"
end

function Keys.Tap(lane, holdTime)
	local kc = lane.Key
	lane.Token = (lane.Token or 0) + 1
	local tok = lane.Token
	if lane.Held then rawKey(false, kc, lane.VK) end
	local ok, backend = rawKey(true, kc, lane.VK)
	if not ok then
		Keys.Failures += 1
		addLog("KEYERR", "No se pudo enviar " .. lane.Label .. " (" .. lane.Name .. "): ningun backend de teclado disponible")
		return false
	end
	Keys.Backend = backend
	Keys.Sent += 1
	lane.Held = true
	pendingDown[kc] = os.clock()
	task.delay(holdTime or 0.05, function()
		if lane.Token == tok then
			rawKey(false, kc, lane.VK)
			lane.Held = false
		end
	end)
	return true
end

local function releaseAll()
	for _, lane in ipairs(LANES) do
		lane.Token = (lane.Token or 0) + 1
		rawKey(false, lane.Key, lane.VK)
		lane.Held = false
	end
end

track(UIS.InputBegan:Connect(function(input)
	local kc = input.KeyCode
	if pendingDown[kc] then
		pendingDown[kc] = nil
		Keys.Confirmed += 1
		if Keys.Streak > 0 then addLog("KEYOK", "Teclas confirmadas de nuevo") end
		Keys.Streak = 0
		if Keys.Confirmed == 1 then addLog("KEYOK", "Primera tecla confirmada por UserInputService (backend " .. Keys.Backend .. ")") end
	end
end))

-- Modo PC opcional: un hook global de __index cuesta FPS, por eso solo se instala si lo activas.
local function installPCSpoof()
	if FNF.SpoofInstalled then return true end
	local ok, err = pcall(function()
		assert(typeof(hookmetamethod) == "function" and typeof(checkcaller) == "function", "hookmetamethod/checkcaller no disponibles")
		local old
		local wrap = typeof(newcclosure) == "function" and newcclosure or function(f) return f end
		old = hookmetamethod(game, "__index", wrap(function(self, key)
			if FNF.SpoofPC and self == UIS and not checkcaller() then
				if key == "TouchEnabled" then return false end
				if key == "KeyboardEnabled" or key == "MouseEnabled" then return true end
			end
			return old(self, key)
		end))
	end)
	if ok then
		FNF.SpoofInstalled = true
		addLog("PC", "Modo PC instalado (TouchEnabled=false, KeyboardEnabled=true para los scripts del juego)")
	else
		addLog("PC", "Modo PC no disponible en este executor: " .. tostring(err))
	end
	return ok
end

-- ============================ GUI BASE ============================
local function mk(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end
local function corner(o, r) return mk("UICorner", {CornerRadius = r == "full" and UDim.new(1, 0) or UDim.new(0, r)}, o) end
local function stroke(o, color, th, tr)
	return mk("UIStroke", {Color = color, Thickness = th, Transparency = tr or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border}, o)
end
local function text(parent, str, size, color, font, xa)
	return mk("TextLabel", {BackgroundTransparency = 1, Text = str, TextSize = size, TextColor3 = color,
		Font = font or Enum.Font.GothamMedium, TextXAlignment = xa or Enum.TextXAlignment.Left}, parent)
end
local function tween(o, t, props) TweenService:Create(o, TweenInfo.new(t, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), props):Play() end

local parentGui
if typeof(gethui) == "function" then pcall(function() parentGui = gethui() end) end
if not parentGui then pcall(function() parentGui = game:GetService("CoreGui") end) end
local gui = mk("ScreenGui", {Name = "CelestialFNF", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 999,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling})
if not (parentGui and pcall(function() gui.Parent = parentGui end)) then gui.Parent = pg end

-- ============================ DETECTOR ============================
local MIN_SZ, MAX_SZ = 24, 260
local cands, tracks = {}, {}
local Field = nil
local Stats = {Pressed = 0, Moving = 0, Statics = 0}
local lastMovingAt, lastFieldCalc = 0, 0
local lastLanePress = {0, 0, 0, 0}

local function addCand(o)
	if (o:IsA("ImageLabel") or o:IsA("ImageButton")) and not o:IsDescendantOf(gui) then
		cands[o] = o:FindFirstAncestorWhichIsA("ScreenGui") or false
	end
end
pcall(function() for _, d in ipairs(pg:GetDescendants()) do addCand(d) end end)
track(pg.DescendantAdded:Connect(addCand))
track(pg.DescendantRemoving:Connect(function(o) cands[o] = nil tracks[o] = nil end))

local function computeField(moving, statics)
	table.sort(statics, function(a, b) return a.y < b.y end)
	local rows, cur = {}, nil
	for _, s in ipairs(statics) do
		if cur and math.abs(s.y - cur.y) <= cur.size * 0.4 then
			if math.abs(s.size - cur.size) <= cur.size * 0.2 then cur.items[#cur.items + 1] = s end
		else
			cur = {y = s.y, size = s.size, items = {s}}
			rows[#rows + 1] = cur
		end
	end
	local best
	for _, row in ipairs(rows) do
		if #row.items >= 4 then
			table.sort(row.items, function(a, b) return a.x < b.x end)
			local cols = {}
			for i = #row.items - 3, #row.items do cols[#cols + 1] = row.items[i] end
			local valid = false
			for _, n in ipairs(moving) do
				local dirv = n.vy > 0 and 1 or -1
				for _, c in ipairs(cols) do
					if math.abs(n.x - c.x) <= c.size * 0.45 and (c.y - n.y) * dirv > -n.size then
						valid = true
						break
					end
				end
				if valid then break end
			end
			if valid and (not best or #row.items > #best.items) then best = {cols = cols, items = row.items} end
		end
	end
	return best
end

local function step()
	local now = os.clock()

	-- Verificacion de teclas enviadas (siempre activa)
	for kc, sentAt in pairs(pendingDown) do
		if now - sentAt > 0.35 then
			pendingDown[kc] = nil
			Keys.Failures += 1
			Keys.Streak += 1
			local lane = LANE_BY_KEY[kc]
			addLog("KEYERR", "Tecla " .. (lane and lane.Label or "?") .. " (" .. (lane and lane.Name or "?") .. ") enviada pero NO confirmada por UserInputService")
			if Keys.Streak == 3 or Keys.Streak % 10 == 0 then
				addLog("KEYERR", string.format("%d teclas seguidas sin confirmar (backend %s): el emulado de teclado puede no estar llegando al juego", Keys.Streak, Keys.Backend))
			end
		end
	end

	if not FNF.Enabled then return end

	local moving, statics = {}, {}
	for o, g in pairs(cands) do
		if o.Parent == nil then
			cands[o] = nil
			tracks[o] = nil
		elseif g and g.Enabled and o.Visible then
			local s = o.AbsoluteSize
			local sx, sy = s.X, s.Y
			if sx >= MIN_SZ and sx <= MAX_SZ and sy >= MIN_SZ and sy <= MAX_SZ and sx / sy > 0.6 and sx / sy < 1.6 then
				local p = o.AbsolutePosition
				local cx, cy = p.X + sx * 0.5, p.Y + sy * 0.5
				local t = tracks[o]
				if not t then
					t = {x = cx, y = cy, t = now, vx = 0, vy = 0, n = 0, size = sx, pressed = false}
					tracks[o] = t
				else
					local dt = now - t.t
					if dt > 0.0005 then
						if dt > 0.25 or math.abs(cy - t.y) > sy * 3 or math.abs(cx - t.x) > sx * 3 then
							t.n, t.vx, t.vy, t.pressed = 0, 0, 0, false
						else
							t.vx = t.vx * 0.5 + ((cx - t.x) / dt) * 0.5
							t.vy = t.vy * 0.5 + ((cy - t.y) / dt) * 0.5
							t.n += 1
						end
						t.x, t.y, t.t, t.size = cx, cy, now, sx
					end
				end
				local avy, avx = math.abs(t.vy), math.abs(t.vx)
				if t.n >= 3 and avy >= 150 and avy <= 8000 and avx <= avy * 0.3 then
					moving[#moving + 1] = t
				elseif t.n >= 20 and avx < 10 and avy < 10 then
					statics[#statics + 1] = t
				end
			else
				tracks[o] = nil
			end
		end
	end

	if #moving > 0 then lastMovingAt = now end

	if now - lastFieldCalc >= 0.25 then
		lastFieldCalc = now
		Stats.Moving, Stats.Statics = #moving, #statics
		local best = computeField(moving, statics)
		if best then
			local sig = string.format("%d|%d|%d|%d", math.floor(best.cols[1].x), math.floor(best.cols[2].x), math.floor(best.cols[3].x), math.floor(best.cols[4].x))
			if not Field or Field.sig ~= sig then
				addLog("FIELD", string.format("Campo detectado: 4 carriles, y=%d, tamano=%d, filas con %d receptores", math.floor(best.cols[1].y), math.floor(best.cols[1].size), #best.items))
				if #best.items > 4 then addLog("FIELD", "Hay mas de 4 receptores en la fila: se usan los 4 de la derecha (campo del jugador)") end
			end
			Field = {cols = best.cols, sig = sig, at = now}
		elseif Field and now - Field.at > 3 then
			Field = nil
			addLog("FIELD", "Campo perdido (sin receptores validados por 3 s)")
		end
		if not Field and #moving > 0 then
			logEvery("nofield", 8, "WARN", string.format("%d objetos en movimiento pero no hay fila de 4 receptores estaticos validada (estaticos=%d)", #moving, #statics))
		elseif #moving == 0 and now - math.max(lastMovingAt, FNF.EnabledAt) > 10 then
			logEvery("nomove", 15, "WARN", "Sin notas en movimiento detectadas (cancion no iniciada, o las flechas no son ImageLabel/ImageButton)")
		end
	end

	if not Field then return end
	local lead = FNF.LeadMs / 1000
	for _, n in ipairs(moving) do
		if not n.pressed then
			local best, bi, bd
			for i, c in ipairs(Field.cols) do
				local d = math.abs(n.x - c.x)
				if not bd or d < bd then best, bi, bd = c, i, d end
			end
			if best and bd <= best.size * 0.45 then
				local dirv = n.vy > 0 and 1 or -1
				local dist = (best.y - n.y) * dirv
				if dist <= math.abs(n.vy) * lead then
					n.pressed = true
					if dist >= -n.size * 0.9 and now - lastLanePress[bi] >= 0.03 then
						lastLanePress[bi] = now
						if Keys.Tap(LANES[bi], 0.05) then
							Stats.Pressed += 1
							if Stats.Pressed <= 20 or Stats.Pressed % 25 == 0 then
								addLog("NOTE", string.format("#%d %s (%s) vel=%d dist=%d", Stats.Pressed, LANES[bi].Name, LANES[bi].Label, math.floor(math.abs(n.vy)), math.floor(dist)))
							end
						end
					end
				end
			end
		end
	end
end
track(RunService.RenderStepped:Connect(step))

function FNF.SetEnabled(v)
	FNF.Enabled = v
	if v then
		FNF.EnabledAt = os.clock()
		addLog("BOT", string.format("Bot ACTIVADO (adelanto %d ms)", FNF.LeadMs))
	else
		releaseAll()
		addLog("BOT", "Bot desactivado")
	end
end

-- ============================ UI ============================
local win = mk("Frame", {Name = "Window", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(300, 270), BackgroundColor3 = C.Dark, Visible = false}, gui)
corner(win, 18)
stroke(win, C.Lilac, 1.5, 0.2)
mk("UIGradient", {Color = ColorSequence.new(C.Dark, C.Purple), Rotation = 90}, win)
local winScale = mk("UIScale", {Scale = 1}, win)

local header = mk("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40)}, win)
local title = text(header, "FNF Remix", 13, C.White, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
title.Position, title.Size, title.TextTruncate = UDim2.fromOffset(42, 0), UDim2.new(1, -84, 1, 0), Enum.TextTruncate.AtEnd

local function smallBtn(str, xScale, xOff)
	local b = mk("TextButton", {AnchorPoint = Vector2.new(xScale, 0.5), Position = UDim2.new(xScale, xOff, 0.5, 0), Size = UDim2.fromOffset(30, 30),
		BackgroundColor3 = C.Button, AutoButtonColor = false, Text = str, TextColor3 = C.White, TextSize = 16, Font = Enum.Font.GothamBold}, header)
	corner(b, "full")
	stroke(b, C.Lilac, 1, 0.55)
	return b
end
local backBtn = smallBtn("<", 0, 8)
local closeBtn = smallBtn("X", 1, -8)

local content = mk("Frame", {BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 1, -40), ClipsDescendants = true}, win)
local function page() return mk("Frame", {BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false}, content) end
local menuPage, botPage, logPage = page(), page(), page()

local function button(parent, str, size, pos, cb, textSize)
	local b = mk("TextButton", {Size = size, Position = pos, BackgroundColor3 = C.Button, AutoButtonColor = false, Text = str,
		TextColor3 = C.White, TextSize = textSize or 14, Font = Enum.Font.GothamBold, TextWrapped = true}, parent)
	corner(b, 12)
	stroke(b, C.Lilac, 1, 0.45)
	b.Activated:Connect(cb)
	return b
end

local function showPage(name)
	menuPage.Visible, botPage.Visible, logPage.Visible = name == "menu", name == "bot", name == "log"
	backBtn.Visible = name ~= "menu"
	title.Text = ({menu = "FNF Remix", bot = "FNF Bot", log = "FNF REMIX KEYS ERROR LOG"})[name]
	FNF.Page = name
	FNF.LogDirty = true
end

-- Menu
button(menuPage, "FNF Bot", UDim2.new(1, -28, 0, 64), UDim2.fromOffset(14, 14), function() showPage("bot") end, 17)
button(menuPage, "FNF REMIX KEYS ERROR LOG", UDim2.new(1, -28, 0, 64), UDim2.fromOffset(14, 90), function() showPage("log") end, 15)
local menuHint = text(menuPage, "", 12, C.Gray)
menuHint.Position, menuHint.Size, menuHint.TextWrapped = UDim2.fromOffset(16, 164), UDim2.new(1, -32, 0, 40), true

-- Toggle
local function toggle(parent, y, str, init, cb)
	local row = mk("Frame", {BackgroundTransparency = 1, Position = UDim2.fromOffset(12, y), Size = UDim2.new(1, -24, 0, 30)}, parent)
	local l = text(row, str, 14, C.White)
	l.Size = UDim2.new(1, -56, 1, 0)
	local pill = mk("TextButton", {AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(46, 24),
		BackgroundColor3 = C.Button, Text = "", AutoButtonColor = false}, row)
	corner(pill, "full")
	stroke(pill, C.Lilac, 1, 0.5)
	local knob = mk("Frame", {AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 3, 0.5, 0), Size = UDim2.fromOffset(18, 18), BackgroundColor3 = C.Silver}, pill)
	corner(knob, "full")
	local state = init
	local function render(animate)
		local props = {Position = state and UDim2.new(1, -21, 0.5, 0) or UDim2.new(0, 3, 0.5, 0), BackgroundColor3 = state and C.Green or C.Silver}
		if animate then tween(knob, 0.2, props) else for k, v in pairs(props) do knob[k] = v end end
	end
	pill.Activated:Connect(function() state = not state render(true) cb(state) end)
	render(false)
end

-- Pagina Bot
toggle(botPage, 10, "FNF Bot", false, function(v) FNF.SetEnabled(v) end)
toggle(botPage, 46, "Modo PC (avanzado)", false, function(v)
	if v and not installPCSpoof() then FNF.SpoofPC = false return end
	FNF.SpoofPC = v
	addLog("PC", v and "Modo PC ACTIVADO" or "Modo PC desactivado")
end)
local leadRow = mk("Frame", {BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 84), Size = UDim2.new(1, -24, 0, 30)}, botPage)
text(leadRow, "Adelanto", 14, C.White).Size = UDim2.new(0.4, 0, 1, 0)
local leadVal = text(leadRow, "", 14, C.MoonBlue, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
leadVal.AnchorPoint, leadVal.Position, leadVal.Size = Vector2.new(1, 0), UDim2.new(1, -40, 0, 0), UDim2.new(0, 60, 1, 0)
local function setLead(v) FNF.LeadMs = math.clamp(v, 0, 120) leadVal.Text = FNF.LeadMs .. " ms" end
setLead(FNF.LeadMs)
button(leadRow, "-", UDim2.fromOffset(32, 28), UDim2.new(1, -104, 0, 1), function() setLead(FNF.LeadMs - 5) end, 18)
button(leadRow, "+", UDim2.fromOffset(32, 28), UDim2.new(1, -32, 0, 1), function() setLead(FNF.LeadMs + 5) end, 18)
local statsLabel = text(botPage, "", 12, C.Silver, Enum.Font.Code)
statsLabel.Position, statsLabel.Size, statsLabel.TextWrapped, statsLabel.TextYAlignment = UDim2.fromOffset(14, 122), UDim2.new(1, -28, 0, 100), true, Enum.TextYAlignment.Top

-- Pagina Log
local keyStatus = text(logPage, "", 12, C.Gray, Enum.Font.GothamBold)
keyStatus.Position, keyStatus.Size, keyStatus.TextTruncate = UDim2.fromOffset(12, 2), UDim2.new(1, -24, 0, 22), Enum.TextTruncate.AtEnd
local scroll = mk("ScrollingFrame", {Position = UDim2.fromOffset(8, 26), Size = UDim2.new(1, -16, 1, -68), BackgroundColor3 = C.Button,
	BorderSizePixel = 0, ScrollBarThickness = 3, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y}, logPage)
corner(scroll, 10)
local logText = text(scroll, "", 11, C.Silver, Enum.Font.Code)
logText.Position, logText.Size, logText.AutomaticSize = UDim2.fromOffset(6, 4), UDim2.new(1, -12, 0, 0), Enum.AutomaticSize.Y
logText.TextWrapped, logText.TextYAlignment, logText.RichText = true, Enum.TextYAlignment.Top, false

local function testKeys()
	if FNF.Testing then return end
	FNF.Testing = true
	addLog("TEST", "Probando Z X , . (se enviara cada tecla una vez)")
	task.spawn(function()
		for _, lane in ipairs(LANES) do
			local before = Keys.Confirmed
			local ok = Keys.Tap(lane, 0.08)
			task.wait(0.45)
			if ok and Keys.Confirmed > before then
				addLog("TEST", lane.Label .. " (" .. lane.Name .. ") OK")
			else
				addLog("TEST", lane.Label .. " (" .. lane.Name .. ") FALLA: sin confirmacion")
			end
		end
		FNF.Testing = false
	end)
end

local function saveLog()
	local str = table.concat(Log.Lines, "\n")
	local saved, copied = false, false
	if typeof(writefile) == "function" then saved = pcall(writefile, "FNFRemix_Log.txt", str) end
	if typeof(setclipboard) == "function" then copied = pcall(setclipboard, str) end
	addLog("LOG", string.format("Guardado=%s Copiado=%s (FNFRemix_Log.txt)", tostring(saved), tostring(copied)))
end

local btnY = UDim2.new(0, 0, 1, -38)
button(logPage, "Probar", UDim2.new(0.31, -8, 0, 32), UDim2.new(0, 8, 1, -38), testKeys, 12)
button(logPage, "Guardar/Copiar", UDim2.new(0.38, -4, 0, 32), UDim2.new(0.31, 0, 1, -38), saveLog, 12)
button(logPage, "Limpiar", UDim2.new(0.31, -8, 0, 32), UDim2.new(0.69, 0, 1, -38), function() Log.Lines = {} FNF.LogDirty = true end, 12)

-- Abrir / cerrar
local function setOpen(v)
	FNF.Open = v
	if v then
		win.Visible = true
		winScale.Scale = 0.88
		tween(winScale, 0.25, {Scale = 1})
		showPage(FNF.Page)
	else
		tween(winScale, 0.18, {Scale = 0.88})
		task.delay(0.2, function() if not FNF.Open then win.Visible = false end end)
	end
end
backBtn.Activated:Connect(function() showPage("menu") end)
closeBtn.Activated:Connect(function() setOpen(false) end)
showPage("menu")

-- Burbuja (arrastrable; un toque abre/cierra)
local bubble = mk("ImageButton", {Name = "Bubble", Size = UDim2.fromOffset(62, 62), Position = UDim2.new(0, 16, 0.5, -31),
	BackgroundColor3 = C.Lilac, AutoButtonColor = false, Image = "", ZIndex = 2}, gui)
corner(bubble, "full")
mk("UIGradient", {Color = ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.fromRGB(214, 208, 255)),
	ColorSequenceKeypoint.new(0.48, Color3.fromRGB(187, 160, 253)), ColorSequenceKeypoint.new(1, Color3.fromRGB(152, 128, 246))}), Rotation = 35}, bubble)
stroke(bubble, C.Lilac, 1.5, 0.1)
local logo = mk("ImageLabel", {BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Image = BUBBLE_ID, ScaleType = Enum.ScaleType.Crop, ZIndex = 3}, bubble)
corner(logo, "full")

do
	local dragging, moved, startPt, startPos = false, false, nil, nil
	bubble.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging, moved, startPt, startPos = true, false, input.Position, bubble.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
					if not moved then setOpen(not FNF.Open) end
				end
			end)
		end
	end)
	track(UIS.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement) then
			local d = input.Position - startPt
			if d.Magnitude > 6 then moved = true end
			if moved then
				bubble.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
			end
		end
	end))
end

-- Refresco de textos (4 Hz)
task.spawn(function()
	while FNF.Running do
		task.wait(0.25)
		if FNF.Open then
			if FNF.Page == "menu" then
				menuHint.Text = string.format("Bot: %s\nTeclas: Z=Left X=Down ,=Up .=Right", FNF.Enabled and "ON" or "OFF")
			elseif FNF.Page == "bot" then
				statsLabel.Text = string.format("Estado: %s\nNotas pulsadas: %d\nEn movimiento: %d | Receptores: %d\nCampo: %s\nTeclas: %d env | %d conf | %d fallas\nBackend: %s",
					FNF.Enabled and "ON" or "OFF", Stats.Pressed, Stats.Moving, Stats.Statics, Field and "4 carriles OK" or "sin detectar",
					Keys.Sent, Keys.Confirmed, Keys.Failures, Keys.Backend)
			elseif FNF.Page == "log" then
				local good = Keys.Confirmed > 0 and Keys.Streak == 0
				keyStatus.TextColor3 = Keys.Streak > 0 and C.Red or (good and C.Green or C.Gray)
				keyStatus.Text = string.format("Teclas: %d env | %d conf | %d fallas | %s", Keys.Sent, Keys.Confirmed, Keys.Failures, Keys.Backend)
				if FNF.LogDirty then
					FNF.LogDirty = false
					local L, first = Log.Lines, math.max(1, #Log.Lines - 149)
					logText.Text = table.concat(L, "\n", first, #L)
					task.defer(function() scroll.CanvasPosition = Vector2.new(0, math.max(0, scroll.AbsoluteCanvasSize.Y - scroll.AbsoluteSize.Y)) end)
				end
			end
		end
	end
end)

function FNF.Destroy()
	FNF.Running = false
	FNF.Enabled = false
	FNF.SpoofPC = false
	pcall(releaseAll)
	for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
	pcall(function() gui:Destroy() end)
	if _G.CelestialFNF == FNF then _G.CelestialFNF = nil end
end

addLog("INFO", "FNF Bot cargado. Toca la burbuja para abrir la ventana.")
