--!nonstrict
-- OCR — control-center quick tile. Mirrors the bar widget's click mapping:
-- left click = OCR a selected region, right click = OCR the focused output.
--
-- Thin client, same as ocr.luau: forwards clicks to the fel/ocr:service
-- entry, which does the actual capture. Keep this in sync with ocr.luau.

local available = noctalia.commandExists("grim")
	and noctalia.commandExists("slurp")
	and noctalia.commandExists("tesseract")

local function render()
	shortcut.setLabel("OCR text grab")
	shortcut.setIcon("scan")
	shortcut.setEnabled(available)
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

render()
