--!nonstrict
-- OCR — bar widget.
--
-- Left click:  ask the fel/ocr:service entry to OCR a slurp-selected region.
-- Right click: same, but for the whole focused output (no selection).
--
-- This widget is a thin client: it only shows the glyph/tooltip and forwards
-- clicks to the headless service over `noctalia msg plugin fel/ocr:service`.
-- The service does the actual capture, notifications, and clipboard copy —
-- see service.luau — so OCR keeps working from a keybind even when this
-- widget isn't placed on a bar. One trade-off: because the click just fires
-- the request and returns, this widget can't show a "capturing…" state the
-- way a self-contained widget could; watch for the result notification
-- instead.

local available = noctalia.commandExists("grim")
	and noctalia.commandExists("slurp")
	and noctalia.commandExists("tesseract")

local function render()
	barWidget.setGlyph(noctalia.getConfig("glyph") or "scan")
	if not available then
		barWidget.setGlyphColor("on_surface_variant")
		barWidget.setTooltip("OCR: missing dependency (needs grim, slurp, tesseract)")
	else
		barWidget.setGlyphColor("on_surface")
		barWidget.setTooltip({
			{ key = "Left click", value = "OCR a region" },
			{ key = "Right click", value = "OCR the focused screen" },
		})
	end
end

local function dispatch(event)
	if not available then
		return
	end
	if not noctalia.runAsync('noctalia msg plugin fel/ocr:service all ' .. event, function(result)
		if result.exitCode ~= 0 then
			noctalia.notifyError("OCR", "Could not reach the OCR service")
		end
	end, 5000) then
		noctalia.notifyError("OCR", "Failed to launch capture command")
	end
end

function onClick()
	dispatch("region")
end

function onRightClick()
	dispatch("screen")
end

function onConfigChanged()
	render()
end

render()
