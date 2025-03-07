local M = {}

local function onDamage(data, data_delta)
    log('I', 'sopo_pacenotes_vehicle', 'onDamage')
    dump(data_delta)
    obj:queueGameEngineLua("extensions.scripts_sopo__pacenotes_extension.onDamage('" .. jsonEncode(data) .. "', '" .. jsonEncode(data_delta) .. "')")
end

local function init()
    log('I', 'sopo_pacenotes_vehicle', 'onInit')
    damageTracker.registerDamageUpdateCallback(M.onDamage)
end

local function onReset()
    log('I', 'sopo_pacenotes_vehicle', 'onReset')
end

M.init = init
M.onReset = onReset
M.onDamage = onDamage

return M
