--[[
	Celestial Hub | FNF Remix Bot V2
	Cambios sobre V1 (a partir del log real):
	- Campo: ya no elige la fila con mas objetos (eran notas aparcadas arriba, y=6). Elige la fila a la que
	  las notas LLEGAN de verdad (puntaje por llegadas) y no cambia por ruido.
	- Tiempo: velocidad por ventana de muestras (antes muy ruidosa), adelanto total = ajuste manual
	  + latencia real medida de las teclas + medio frame.
	- Rendimiento: los objetos estaticos y los descartados se revisan con poca frecuencia (antes ~950 por frame).
	- Resultado por nota (inferido: la nota desaparece cerca del receptor = acierto) y distancia al recibir la tecla.
	- Interfaz: el numero del adelanto quedaba tapado por el boton "-".
	Teclas: Left = Z | Down = X | Up = Comma (,) | Right = Period (.)
	VERSION EXPERIMENTAL: no probada en el juego.
]]

if _G.CelestialFNF and type(_G.CelestialFNF.Destroy) == "function" then
	pcall(_G.CelestialFNF.Destroy)
end

local FNF = {Enabled = false, SpoofPC = false, LeadMs = 30, EnabledAt = 0, Page = "menu", Open = false, Running = true, LogDirty = true}
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

addLog("INFO", string.format("V2 | VIM=%s keypress=%s Teclado=%s Touch=%s", tostring(VIM ~= nil),
	tostring(typeof(keypress) == "function"), tostring(UIS.KeyboardEnabled), tostring(UIS.TouchEnabled)))

-- ============================ TECLAS ============================
local pendingDown = {}
local Keys = {Sent = 0, Confirmed = 0, Failures = 0, Streak = 0, Backend = "-", Latency = 0.03, LatencyN = 0}

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
	local sentAt = pendingDown[kc]
	if sentAt then
		pendingDown[kc] = nil
		-- Latencia real entre enviar la tecla y que el juego la recibe (mismo evento que ve el juego).
		local lat = math.clamp(os.clock() - sentAt, 0, 0.25)
		Keys.Latency = Keys.LatencyN == 0 and lat or (Keys.Latency * 0.8 + lat * 0.2)
		Keys.LatencyN += 1
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
local cands, tracks, rejectUntil = {}, {}, {}
local Rows, Field = {}, nil
local Stats = {Pressed = 0, Hits = 0, Misses = 0, Moving = 0, Statics = 0}
local Perf = {dt = 1 / 60}
local Pend = {}
local lastMovingAt, lastFieldCalc, lastStepAt = 0, 0, 0
local lastLanePress = {0, 0, 0, 0}

local function addCand(o)
	if (o:IsA("ImageLabel") or o:IsA("ImageButton")) and not o:IsDescendantOf(gui) then
		cands[o] = o:FindFirstAncestorWhichIsA("ScreenGui") or false
	end
end
pcall(function() for _, d in ipairs(pg:GetDescendants()) do addCand(d) end end)
track(pg.DescendantAdded:Connect(addCand))
track(pg.DescendantRemoving:Connect(function(o) cands[o] = nil tracks[o] = nil rejectUntil[o] = nil end))

local function resetTrack(t, cx, cy, now)
	t.prevY = t.y
	t.n, t.vx, t.vy = 1, 0, 0
	t.hist = {{now, cx, cy}}
	t.pressed, t.scored, t.static = false, false, false
	t.x0, t.y0 = cx, cy
	t.x, t.y, t.t = cx, cy, now
	t.resets += 1
end

-- Revisa un objeto candidato; agrega a `moving` si se mueve como una nota.
local function process(o, g, t, now, moving)
	if not (g and g.Enabled and o.Visible) then
		rejectUntil[o] = now + 0.5
		tracks[o] = nil
		return
	end
	local s = o.AbsoluteSize
	local sx, sy = s.X, s.Y
	if not (sx >= MIN_SZ and sx <= MAX_SZ and sy >= MIN_SZ and sy <= MAX_SZ and sx / sy > 0.6 and sx / sy < 1.6) then
		rejectUntil[o] = now + 0.5
		tracks[o] = nil
		return
	end
	local p = o.AbsolutePosition
	local cx, cy = p.X + sx * 0.5, p.Y + sy * 0.5
	if not t then
		tracks[o] = {o = o, x = cx, y = cy, x0 = cx, y0 = cy, prevY = cy, t = now, n = 1, size = sx, vx = 0, vy = 0,
			hist = {{now, cx, cy}}, resets = 0, pressed = false, scored = false, static = false}
		return
	end
	t.size = sx
	if t.static then
		if math.abs(cy - t.y) + math.abs(cx - t.x) > 1.5 then
			resetTrack(t, cx, cy, now)
		else
			t.x, t.y, t.t = cx, cy, now
		end
		return
	end
	if now - t.t > 0.25 or math.abs(cy - t.y) > sy * 3 or math.abs(cx - t.x) > sx * 3 then
		resetTrack(t, cx, cy, now)
		return
	end
	local h = t.hist
	h[#h + 1] = {now, cx, cy}
	if #h > 7 then table.remove(h, 1) end
	t.x, t.y, t.t = cx, cy, now
	t.n += 1
	if #h >= 3 then
		local a, b = h[1], h[#h]
		local span = b[1] - a[1]
		if span >= 0.05 then
			t.vx = (b[2] - a[2]) / span
			t.vy = (b[3] - a[3]) / span
		end
	end
	local avy, avx = math.abs(t.vy), math.abs(t.vx)
	if #h >= 4 and avy >= 150 and avy <= 8000 and avx <= avy * 0.3 then
		moving[#moving + 1] = t
	elseif t.n >= 12 and avx < 8 and avy < 8 then
		t.static = true
		t.hist = {}
	end
end

-- Agrupa receptores estaticos en filas y mantiene el puntaje de llegadas de cada fila.
local function rebuildRows(now)
	local statics = {}
	for _, t in pairs(tracks) do
		if t.static then statics[#statics + 1] = t end
	end
	Stats.Statics = #statics
	table.sort(statics, function(a, b) return a.y < b.y end)
	local groups, cur = {}, nil
	for _, s in ipairs(statics) do
		if cur and math.abs(s.y - cur.y) <= cur.size * 0.4 then
			if math.abs(s.size - cur.size) <= cur.size * 0.2 then cur.items[#cur.items + 1] = s end
		else
			cur = {y = s.y, size = s.size, items = {s}}
			groups[#groups + 1] = cur
		end
	end
	for _, grp in ipairs(groups) do
		if #grp.items >= 4 then
			table.sort(grp.items, function(a, b) return a.x < b.x end)
			local cols = {}
			for _, it in ipairs(grp.items) do
				local last = cols[#cols]
				if not last or it.x - last.x > grp.size * 0.3 then cols[#cols + 1] = it end
			end
			if #cols >= 4 then
				local entry
				for _, e in ipairs(Rows) do
					if math.abs(e.y - grp.y) <= grp.size * 0.4 and math.abs(e.size - grp.size) <= grp.size * 0.2 then
						entry = e
						break
					end
				end
				if not entry then
					entry = {y = grp.y, size = grp.size, score = 0}
					Rows[#Rows + 1] = entry
				end
				entry.y, entry.size, entry.seen, entry.cols = grp.y, grp.size, now, cols
			end
		end
	end
	for i = #Rows, 1, -1 do
		if now - (Rows[i].seen or 0) > 20 then
			if Field == Rows[i] then Field = nil end
			table.remove(Rows, i)
		end
	end
	if Field and now - Field.seen > 3 then
		Field = nil
		addLog("FIELD", "Campo perdido (receptores no visibles por 3 s)")
	end
	local best
	for _, e in ipairs(Rows) do
		if e.score >= 1 and now - e.seen <= 3 and (not best or e.score > best.score) then best = e end
	end
	if best and best ~= Field and (not Field or best.score >= Field.score + 3) then
		Field = best
		local nc = #best.cols
		addLog("FIELD", string.format("Campo: y=%d tamano=%d columnas=%d llegadas=%d%s", math.floor(best.y), math.floor(best.size), nc,
			best.score, nc > 4 and " (se usan las 4 de la derecha)" or ""))
	end
end

local function step()
	local now = os.clock()
	local dtf = math.min(now - lastStepAt, 0.2)
	lastStepAt = now
	if dtf > 0 then Perf.dt = Perf.dt * 0.9 + dtf * 0.1 end

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

	local moving = {}
	for o, g in pairs(cands) do
		if o.Parent == nil then
			cands[o] = nil
			tracks[o] = nil
			rejectUntil[o] = nil
		else
			local rej = rejectUntil[o]
			local t = tracks[o]
			if not ((rej and now < rej) or (t and t.static and now - t.t < 0.2)) then
				process(o, g, t, now, moving)
			end
		end
	end

	Stats.Moving = #moving
	if #moving > 0 then lastMovingAt = now end

	if now - lastFieldCalc >= 0.25 then
		lastFieldCalc = now
		rebuildRows(now)
		if not Field and #moving > 0 then
			logEvery("nofield", 8, "WARN", string.format("%d notas en movimiento; calibrando campo (filas candidatas=%d, aun sin llegadas validas)", #moving, #Rows))
		elseif #moving == 0 and now - math.max(lastMovingAt, FNF.EnabledAt) > 10 then
			logEvery("nomove", 15, "WARN", "Sin notas en movimiento detectadas (cancion no iniciada, o las flechas no son ImageLabel/ImageButton)")
		end
	end

	-- Puntaje de llegadas: la fila correcta es a la que las notas llegan (no la que solo tiene muchos objetos).
	for _, n in ipairs(moving) do
		if not n.scored and math.abs(n.y - n.y0) > n.size * 3 then
			local dirv = n.vy > 0 and 1 or -1
			for _, e in ipairs(Rows) do
				local dist = (e.y - n.y) * dirv
				if dist >= 0 and dist < n.size * 0.9 and e.cols then
					for _, c in ipairs(e.cols) do
						if math.abs(n.x - c.x) <= c.size * 0.45 then
							e.score += 1
							n.scored = true
							break
						end
					end
				end
				if n.scored then break end
			end
		end
	end

	-- Resultado de cada pulsacion (inferido: la nota desaparece cerca del receptor = acierto)
	for i = #Pend, 1, -1 do
		local p = Pend[i]
		local t = p.t
		local o = t.o
		local gone = o.Parent == nil or not o.Visible or tracks[o] ~= t or t.resets ~= p.resets
		local elapsed = now - p.at
		if gone then
			table.remove(Pend, i)
			local ly = (t.resets ~= p.resets) and t.prevY or t.y
			if elapsed <= 0.6 and math.abs(p.ry - ly) <= p.size * 1.3 then
				Stats.Hits += 1
				if Stats.Hits <= 10 or Stats.Hits % 20 == 0 then
					addLog("HIT", string.format("%s dist al pulsar=%d | al recibir el juego la tecla=%d px", LANES[p.lane].Name, math.floor(p.dist), math.floor(p.dist - p.v * Keys.Latency)))
				end
			else
				Stats.Misses += 1
				logEvery("miss", 0.25, "MISS", string.format("%s salio de pantalla lejos del receptor (dist al pulsar=%d)", LANES[p.lane].Name, math.floor(p.dist)))
			end
		elseif elapsed > 0.35 then
			table.remove(Pend, i)
			Stats.Misses += 1
			local dnow = (p.ry - t.y) * p.dirv
			logEvery("miss", 0.25, "MISS", string.format("%s la nota sigue visible | dist al pulsar=%d | al recibir=%d | ahora=%d px (negativo = ya paso)",
				LANES[p.lane].Name, math.floor(p.dist), math.floor(p.dist - p.v * Keys.Latency), math.floor(dnow)))
		end
	end

	if not Field or not Field.cols then return end
	local cols, nc = Field.cols, #Field.cols
	if nc < 4 then return end
	local leadTotal = FNF.LeadMs / 1000 + Keys.Latency + Perf.dt * 0.5
	for _, n in ipairs(moving) do
		if not n.pressed then
			local bi, bc, bd
			for i = nc - 3, nc do
				local d = math.abs(n.x - cols[i].x)
				if not bd or d < bd then bi, bc, bd = i - (nc - 4), cols[i], d end
			end
			if bc and bd <= bc.size * 0.45 then
				local dirv = n.vy > 0 and 1 or -1
				local dist = (Field.y - n.y) * dirv
				local v = math.abs(n.vy)
				if dist <= v * leadTotal then
					n.pressed = true
					if dist >= -n.size * 0.9 and now - lastLanePress[bi] >= 0.03 then
						lastLanePress[bi] = now
						if Keys.Tap(LANES[bi], 0.05) then
							Stats.Pressed += 1
							if #Pend < 40 then
								Pend[#Pend + 1] = {t = n, lane = bi, at = now, dist = dist, v = v, dirv = dirv, ry = Field.y, size = n.size, resets = n.resets}
							end
							if Stats.Pressed <= 15 or Stats.Pressed % 25 == 0 then
								addLog("NOTE", string.format("#%d %s (%s) vel=%d dist=%d adelanto=%dms", Stats.Pressed, LANES[bi].Name, LANES[bi].Label,
									math.floor(v), math.floor(dist), math.floor(leadTotal * 1000)))
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
		addLog("BOT", string.format("Bot ACTIVADO (ajuste manual %d ms)", FNF.LeadMs))
	else
		releaseAll()
		Pend = {}
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

-- Fila de ajuste: [Adelanto extra] ....... [-] [valor] [+]  (sin solapes: el valor ya no queda tapado)
local leadRow = mk("Frame", {BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 84), Size = UDim2.new(1, -24, 0, 30)}, botPage)
local leadLbl = text(leadRow, "Adelanto extra", 14, C.White)
leadLbl.Size = UDim2.new(0, 110, 1, 0)
local leadVal = text(leadRow, "", 14, C.MoonBlue, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
leadVal.AnchorPoint, leadVal.Position, leadVal.Size = Vector2.new(1, 0), UDim2.new(1, -36, 0, 0), UDim2.fromOffset(62, 30)
local function setLead(v)
	FNF.LeadMs = math.clamp(v, 0, 250)
	leadVal.Text = tostring(FNF.LeadMs) .. " ms"
end
setLead(FNF.LeadMs)
button(leadRow, "-", UDim2.fromOffset(32, 28), UDim2.new(1, -136, 0, 1), function() setLead(FNF.LeadMs - 5) end, 18)
button(leadRow, "+", UDim2.fromOffset(32, 28), UDim2.new(1, -32, 0, 1), function() setLead(FNF.LeadMs + 5) end, 18)

local statsLabel = text(botPage, "", 12, C.Silver, Enum.Font.Code)
statsLabel.Position, statsLabel.Size, statsLabel.TextWrapped, statsLabel.TextYAlignment = UDim2.fromOffset(14, 124), UDim2.new(1, -28, 0, 96), true, Enum.TextYAlignment.Top

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
		addLog("TEST", string.format("Latencia de tecla medida: %d ms", math.floor(Keys.Latency * 1000)))
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
				local total = FNF.LeadMs + Keys.Latency * 1000 + Perf.dt * 500
				statsLabel.Text = string.format("Estado: %s | Campo: %s\nPulsadas: %d | Acierto*: %d / Fallo*: %d\nNotas mov: %d | Estaticos: %d\nTeclas: %d env %d conf %d fallas (%s)\nAdelanto total: %d ms (tecla %d + frame %d)",
					FNF.Enabled and "ON" or "OFF", Field and "OK" or "calibrando", Stats.Pressed, Stats.Hits, Stats.Misses,
					Stats.Moving, Stats.Statics, Keys.Sent, Keys.Confirmed, Keys.Failures, Keys.Backend,
					math.floor(total), math.floor(Keys.Latency * 1000), math.floor(Perf.dt * 500))
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

addLog("INFO", "FNF Bot V2 cargado. Toca la burbuja para abrir la ventana.")
