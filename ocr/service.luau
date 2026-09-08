--!nonstrict
-- OCR — headless capture service.
--
-- Owns the actual capture pipeline (slurp -> grim -> tesseract -> clipboard)
-- so it keeps working whether or not the bar widget or control-center
-- shortcut is placed anywhere. Services run for the whole session as soon as
-- the plugin is enabled, unlike widgets/shortcuts which only run while an
-- instance of them exists somewhere.
--
-- Triggered by:  noctalia msg plugin fel/ocr:service all region
--                noctalia msg plugin fel/ocr:service all screen
-- (bind either line to a compositor keybind, or call it from the widget /
-- shortcut, which both do exactly this over noctalia.runAsync).
--
-- Exit codes partition the failure modes: 40 = selection cancelled (silent),
-- 41 = mktemp, 42 = grim, 43 = tesseract. The temp PNG is created only after
-- the slurp selection succeeds, and an EXIT trap removes it on every path.

local busy = false
local available = noctalia.commandExists("grim")
	and noctalia.commandExists("slurp")
	and noctalia.commandExists("tesseract")

local function shellQuote(s)
	return "'" .. string.gsub(s, "'", "'\\''") .. "'"
end

-- One shell pipeline: geometry -> screenshot -> tesseract -> stdout.
-- wholeOutput = true skips slurp and captures the focused output instead.
local function buildCommand(wholeOutput)
	local langs = string.gsub(tostring(noctalia.getConfig("languages") or "eng"), "[^%w_+]", "")
	if langs == "" then
		langs = "eng"
	end
	local psm = string.gsub(tostring(noctalia.getConfig("psm") or "6"), "%D", "")
	if psm == "" then
		psm = "6"
	end

	local mktemp = 'img="$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/noctalia-ocr-XXXXXX.png")" || exit 41; '
	local pipeline
	if wholeOutput then
		local out = noctalia.focusedOutputName()
		local target = if out then "-o " .. shellQuote(out) .. " " else ""
		pipeline = mktemp .. 'grim ' .. target .. '"$img" || exit 42; '
	else
		pipeline = 'geom="$(slurp)" || exit 40; ' .. mktemp .. 'grim -g "$geom" "$img" || exit 42; '
	end

	return 'trap \'rm -f "$img" 2>/dev/null\' EXIT; '
		.. pipeline
		.. 'txt="$(tesseract "$img" stdout -l ' .. langs .. ' --psm ' .. psm .. ' 2>/dev/null)"; rc=$?; '
		.. '[ "$rc" -ne 0 ] && exit 43; printf "%s" "$txt"'
end

local function handleResult(result)
	busy = false

	if result.timedOut then
		noctalia.notifyError("OCR", "Timed out — selection must finish within 60 seconds")
		return
	end
	if result.exitCode == 40 then
		return -- selection cancelled by the user
	end
	if result.exitCode == 42 then
		noctalia.notifyError("OCR", "Screenshot failed (grim)")
		return
	end
	if result.exitCode ~= 0 then
		noctalia.notifyError("OCR", "Text recognition failed (exit " .. tostring(result.exitCode) .. ")")
		return
	end

	local text = noctalia.string.trim(result.stdout)
	if text == "" then
		noctalia.notify("OCR", "No text recognized in the selection")
		return
	end

	if noctalia.getConfig("copy_to_clipboard") ~= false then
		noctalia.copyToClipboard(text, "text/plain")
	end
	if noctalia.getConfig("show_notification") ~= false then
		local preview = if #text > 160 then string.sub(text, 1, 157) .. "…" else text
		local suffix = if result.stdoutTruncated then " (output truncated)" else ""
		noctalia.notify("OCR — copied" .. suffix, preview)
	end
end

local function grab(wholeOutput)
	if not available then
		noctalia.notifyError("OCR", "Missing dependency (needs grim, slurp, tesseract)")
		return
	end
	if busy then
		return
	end
	busy = true
	if not noctalia.runAsync(buildCommand(wholeOutput), handleResult, 60000) then
		busy = false
		noctalia.notifyError("OCR", "Failed to launch capture command")
	end
end

function onIpc(event, payload)
	if event == "region" then
		grab(false)
	elseif event == "screen" then
		grab(true)
	end
end
