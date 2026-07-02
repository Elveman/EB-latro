local mod = SMODS.current_mod

local buttplug = nil
local isConnected = false
local isConnecting = false
local initFailed = false
local initError = nil

local vibrationEndTime = 0
local lastSendTime = 0
local MIN_SEND_INTERVAL = 0.08
local MIN_HOLD_AFTER_BUMP = 1.5
local MAX_SCORING_DURATION = 30.0

local scoringActive = false
local scoringStartTime = 0
local scoringIntensity = 0

local currentAnte = 1

local blindExceededActive = false
local blindExceededIntensity = 0

local overlayState = { text = "0%" }
local overlayUIBox = nil
local overlayAnchor = nil

local function sendRaw(percent)
    if isConnected and not initFailed and buttplug then
        local ok = pcall(function()
            buttplug.send_vibrate_cmd(0, { percent })
        end)
        if not ok then
            isConnected = false
        end
    end
end

function calculateFinalIntensity()
    local intensities = {}
    
    if scoringActive and scoringIntensity > 0 then
        table.insert(intensities, scoringIntensity)
    end
    
    if mod.config.constant_enabled and G.STAGE == G.STAGES.RUN then
        local currentConstant = (mod.config.constant_start + 
                            (currentAnte - 1) * mod.config.constant_ante_increment) / 100
        currentConstant = math.min(1, math.max(0, currentConstant))
        if currentConstant > 0 then
            table.insert(intensities, currentConstant)
        end
    end
    
    if blindExceededActive and blindExceededIntensity > 0 then
        table.insert(intensities, blindExceededIntensity)
    end
    
    if #intensities == 0 then
        return 0
    end
    
    if mod.config.blend_mode == 1 then
        local max = 0
        for _, v in ipairs(intensities) do
            max = math.max(max, v)
        end
        return max
    else
        local sum = 0
        for _, v in ipairs(intensities) do
            sum = sum + v
        end
        return math.min(1, sum)
    end
end

function sendFinalVibration()
    local intensity = calculateFinalIntensity()
    local now = G.TIMERS and G.TIMERS.REAL or 0

    overlayState.text = "Vibration: " .. math.floor(intensity * 100 + 0.5) .. "%"

    if intensity > 0 then
        vibrationEndTime = math.max(vibrationEndTime, now + MIN_HOLD_AFTER_BUMP)
    end
    
    if now - lastSendTime >= MIN_SEND_INTERVAL then
        sendRaw(intensity)
        lastSendTime = now
    end
end

local function destroyOverlay()
    if overlayUIBox then
        overlayUIBox:remove()
        overlayUIBox = nil
    end
    overlayAnchor = nil
end

local function createOverlay()
    if overlayUIBox then return end
    if not (G.HUD and G.ROOM_ATTACH) then return end

    overlayUIBox = UIBox{
        definition = {
            n = G.UIT.ROOT,
            config = { align = "cm", padding = 0.05, colour = G.C.CLEAR },
            nodes = {
                {
                    n = G.UIT.O,
                    config = {
                        object = DynaText({
                            string = { { ref_table = overlayState, ref_value = "text" } },
                            colours = { G.C.WHITE },
                            shadow = true,
                            scale = 0.4
                        })
                    }
                }
            }
        },
        config = {
            align = "tm",
            offset = { x = 0, y = -0.6 },
            major = G.ROOM_ATTACH
        }
    }
    overlayAnchor = G.ROOM_ATTACH
end

function updateEBOverlay()
    if mod.config.show_overlay then
        -- If the anchor (G.ROOM_ATTACH) was replaced (e.g. new run started),
        -- rebuild the overlay against the current one.
        if overlayUIBox and overlayAnchor ~= G.ROOM_ATTACH then
            destroyOverlay()
        end
        createOverlay()
    else
        destroyOverlay()
    end
end

function hasSustainedVibrationSource()
    return scoringActive or (mod.config.constant_enabled and G.STAGE == G.STAGES.RUN) or blindExceededActive
end

function bumpVibration(amount)
    if not (isConnected and not initFailed and buttplug) then return end
    if not scoringActive then return end
    
    scoringIntensity = math.min(1, scoringIntensity + amount)
    sendFinalVibration()
end

function updateEBAnte()
    if G.GAME and G.GAME.round_resets and G.GAME.round_resets.ante then
        local newAnte = G.GAME.round_resets.ante
        if newAnte ~= currentAnte then
            currentAnte = newAnte
        end
    end
end

function checkBlindExceeded()
    if not G.GAME or not G.GAME.blind then return end

    -- G.GAME.blind.chips is reset to 0 between blinds (round eval, shop,
    -- blind select) before the next blind is actually chosen/started. During
    -- that window the round score is also 0, so a naive `score >= chips`
    -- check would read as "exceeded" (0 >= 0) and falsely trigger this mode.
    -- Only evaluate once there's a real blind requirement to compare against.
    if not G.GAME.blind.chips or G.GAME.blind.chips <= 0 then
        if blindExceededActive then
            blindExceededActive = false
            blindExceededIntensity = 0
            sendFinalVibration()
        end
        return
    end

    local exceeded = SMODS.calculate_round_score() >= G.GAME.blind.chips
    
    if exceeded and not blindExceededActive then
        blindExceededActive = true
        if mod.config.blind_exceeded_mode == 2 then
            blindExceededIntensity = 0.2
        elseif mod.config.blind_exceeded_mode == 3 then
            blindExceededIntensity = 0.5
        elseif mod.config.blind_exceeded_mode == 4 then
            blindExceededIntensity = 1.0
        else
            blindExceededIntensity = 0
        end
        sendFinalVibration()
    elseif not exceeded and blindExceededActive then
        blindExceededActive = false
        blindExceededIntensity = 0
        sendFinalVibration()
    end
end

if not _buttplug_original_play_sound then
    _buttplug_original_play_sound = play_sound

    play_sound = function(sound, pitch, volume)
        if G.STATE == G.STATES.HAND_PLAYED then
            if sound == 'chips2' and (not pitch or pitch == 0) then
                if not scoringActive then
                    scoringActive = true
                    scoringStartTime = G.TIMERS and G.TIMERS.REAL or 0
                    scoringIntensity = mod.config.start_intensity / 100
                    lastSendTime = 0
                    sendFinalVibration()
                else
                    scoringActive = false
                    scoringIntensity = 0
                    sendFinalVibration()
                end
            elseif sound == 'chips1' or sound == 'multhit1'
                or sound == 'multhit2' or sound == 'xchips' or sound == 'coin3' then
                bumpVibration(mod.config.trigger_increment / 100)
            end
        end
        return _buttplug_original_play_sound(sound, pitch, volume)
    end
end

local function connect_to_intiface()
    local ok, bp
    ok, bp = pcall(require, "eb_latro_buttplug")
    if not ok then
        initFailed = true
        initError = tostring(bp)
        sendErrorMessage("Failed to load buttplug module: " .. initError, "EB-latro")
        return
    end
    buttplug = bp

    table.insert(buttplug.cb.ServerInfo, function()
        isConnected = true
        isConnecting = false
        sendInfoMessage("Connected to Intiface server", "EB-latro")
        buttplug.request_device_list()
        
        if G.GAME and G.GAME.round_resets and G.GAME.round_resets.ante then
            currentAnte = G.GAME.round_resets.ante
        end
    end)

    table.insert(buttplug.cb.DeviceList, function()
        if buttplug.count_devices() == 0 then
            buttplug.start_scanning()
        end
    end)

    table.insert(buttplug.cb.DeviceAdded, function()
        buttplug.stop_scanning()
    end)

    table.insert(buttplug.cb.DeviceRemoved, function()
        buttplug.start_scanning()
    end)

    local server_addr = mod.config.server_address or "ws://127.0.0.1:12345"
    local conn_ok, conn_err = pcall(function()
        buttplug.connect("EB-latro", server_addr)
    end)

    if conn_ok then
        isConnecting = true
    else
        initFailed = true
        initError = tostring(conn_err)
        sendErrorMessage("Failed to connect: " .. initError, "EB-latro")
    end
end

function pollButtplugMessages()
    updateEBAnte()
    checkBlindExceeded()
    updateEBOverlay()

    if buttplug and (isConnecting or isConnected) then
        local now = G.TIMERS and G.TIMERS.REAL or 0

        if scoringActive and now - scoringStartTime > MAX_SCORING_DURATION then
            scoringActive = false
            scoringIntensity = 0
            sendFinalVibration()
        end

        -- Keep re-evaluating/refreshing intensity every frame while a
        -- sustained source (Constant Mode, Blind Exceeded, active scoring)
        -- is on, so the auto-stop timer below (meant only for decaying bump
        -- vibrations after a scoring event ends) doesn't cut them off.
        -- Skip this while a manual test vibration is active (vibrationEndTime
        -- set to -1 by the Start Test button) so it isn't immediately
        -- overridden/stopped by this loop.
        if isConnected and vibrationEndTime ~= -1 and hasSustainedVibrationSource() then
            sendFinalVibration()
        end

        if isConnected and vibrationEndTime > 0 and now >= vibrationEndTime and not scoringActive then
            vibrationEndTime = 0
            pcall(function()
                buttplug.send_vibrate_cmd(0, { 0 })
            end)
        end

        local polls = 0
        while polls < 10 do
            local ok, msg = pcall(buttplug.get_and_handle_message)
            polls = polls + 1
            if not ok then
                if type(msg) == "string" and (msg == "closed" or msg:find("error")) then
                    if isConnecting then
                        initFailed = true
                        initError = "Intiface server not running at " .. (mod.config.server_address or "ws://127.0.0.1:12345")
                        sendErrorMessage("EB-latro: " .. initError, "EB-latro")
                    end
                    isConnecting = false
                    isConnected = false
                end
                break
            end
            if not msg or msg == "" then
                break
            end
            if msg == "closed" or (type(msg) == "string" and msg:find("error")) then
                if isConnecting then
                    initFailed = true
                    initError = "Intiface server not running at " .. (mod.config.server_address or "ws://127.0.0.1:12345")
                    sendErrorMessage("EB-latro: " .. initError, "EB-latro")
                end
                isConnecting = false
                isConnected = false
                break
            end
        end
    end
end

function G.FUNCS.eb_latro_option_cycle_callback(e)
    if e.cycle_config and e.cycle_config.ref_table and e.cycle_config.ref_value then
        e.cycle_config.ref_table[e.cycle_config.ref_value] = e.to_key
    end
end

function G.FUNCS.eb_latro_start_test()
    sendRaw(0.5)
    vibrationEndTime = -1
end

function G.FUNCS.eb_latro_stop_test()
    sendRaw(0)
    vibrationEndTime = 0
end

mod.config_tab = function()
    local nodes = {}

    if initFailed then
        table.insert(nodes, {
            n = G.UIT.R,
            config = { align = "cm", padding = 0.05 },
            nodes = {
                {
                    n = G.UIT.T,
                    config = {
                        text = "Error: " .. (initError or "Unknown"),
                        colour = G.C.RED,
                        scale = 0.4
                    }
                }
            }
        })
    elseif isConnected then
        table.insert(nodes, {
            n = G.UIT.R,
            config = { align = "cm", padding = 0.05 },
            nodes = {
                {
                    n = G.UIT.T,
                    config = {
                        text = "Connected to Intiface server",
                        colour = G.C.GREEN,
                        scale = 0.4
                    }
                }
            }
        })
    elseif isConnecting then
        table.insert(nodes, {
            n = G.UIT.R,
            config = { align = "cm", padding = 0.05 },
            nodes = {
                {
                    n = G.UIT.T,
                    config = {
                        text = "Connecting...",
                        colour = G.C.UI.TEXT_LIGHT,
                        scale = 0.4
                    }
                }
            }
        })
    else
        table.insert(nodes, {
            n = G.UIT.R,
            config = { align = "cm", padding = 0.05 },
            nodes = {
                {
                    n = G.UIT.T,
                    config = {
                        text = "Not connected",
                        colour = G.C.UI.TEXT_LIGHT,
                        scale = 0.4
                    }
                }
            }
        })
    end

    table.insert(nodes, {
        n = G.UIT.R,
        config = { align = "cm", padding = 0.05 },
        nodes = {
            {
                n = G.UIT.T,
                config = {
                    text = "━━━ Scoring Mode ━━━",
                    colour = G.C.UI.TEXT_LIGHT,
                    scale = 0.35
                }
            }
        }
    })

    table.insert(nodes, {
        n = G.UIT.R,
        config = { align = "cm", padding = 0.05 },
        nodes = {
            {
                n = G.UIT.C,
                config = { align = "cm", padding = 0.15 },
                nodes = {
                    create_slider({
                        label = "Start Intensity (%)", w = 4, h = 0.4,
                        ref_table = mod.config, ref_value = "start_intensity",
                        min = 0, max = 50, decimal_places = 0
                    })
                }
            },
            {
                n = G.UIT.C,
                config = { align = "cm", padding = 0.15 },
                nodes = {
                    create_slider({
                        label = "Trigger Increment (%)", w = 4, h = 0.4,
                        ref_table = mod.config, ref_value = "trigger_increment",
                        min = 0, max = 10, decimal_places = 0
                    })
                }
            }
        }
    })

    table.insert(nodes, {
        n = G.UIT.R,
        config = { align = "cm", padding = 0.05 },
        nodes = {
            {
                n = G.UIT.T,
                config = {
                    text = "━━━ Constant Mode ━━━",
                    colour = G.C.UI.TEXT_LIGHT,
                    scale = 0.35
                }
            }
        }
    })

    table.insert(nodes, {
        n = G.UIT.R,
        config = { align = "cm", padding = 0.05 },
        nodes = {
            {
                n = G.UIT.C,
                config = { align = "cm", padding = 0.15 },
                nodes = {
                    create_toggle({
                        label = "Enable Constant Vibration",
                        ref_table = mod.config,
                        ref_value = "constant_enabled"
                    })
                }
            }
        }
    })

    table.insert(nodes, {
        n = G.UIT.R,
        config = { align = "cm", padding = 0.05 },
        nodes = {
            {
                n = G.UIT.C,
                config = { align = "cm", padding = 0.15 },
                nodes = {
                    create_slider({
                        label = "Constant Start (%)", w = 4, h = 0.4,
                        ref_table = mod.config, ref_value = "constant_start",
                        min = 0, max = 50, decimal_places = 0
                    })
                }
            },
            {
                n = G.UIT.C,
                config = { align = "cm", padding = 0.15 },
                nodes = {
                    create_slider({
                        label = "Ante Increment (%)", w = 4, h = 0.4,
                        ref_table = mod.config, ref_value = "constant_ante_increment",
                        min = 0, max = 20, decimal_places = 0
                    })
                }
            }
        }
    })

    table.insert(nodes, {
        n = G.UIT.R,
        config = { align = "cm", padding = 0.15 },
        nodes = {
            {
                n = G.UIT.C,
                config = { align = "cm", padding = 0.05 },
                nodes = {
                    {
                        n = G.UIT.C,
                        config = {
                            align = "cm",
                            padding = 0.1,
                            minh = 0.6,
                            r = 0.1,
                            hover = true,
                            colour = G.C.GREEN,
                            button = "eb_latro_start_test",
                            shadow = true
                        },
                        nodes = {
                            {
                                n = G.UIT.T,
                                config = {
                                    colour = G.C.UI.TEXT_LIGHT,
                                    scale = 0.4,
                                    text = "Start Test Vibration"
                                }
                            }
                        }
                    }
                }
            },
            {
                n = G.UIT.C,
                config = { align = "cm", padding = 0.05 },
                nodes = {
                    {
                        n = G.UIT.C,
                        config = {
                            align = "cm",
                            padding = 0.1,
                            minh = 0.6,
                            r = 0.1,
                            hover = true,
                            colour = G.C.RED,
                            button = "eb_latro_stop_test",
                            shadow = true
                        },
                        nodes = {
                            {
                                n = G.UIT.T,
                                config = {
                                    colour = G.C.UI.TEXT_LIGHT,
                                    scale = 0.4,
                                    text = "Stop Test Vibration"
                                }
                            }
                        }
                    }
                }
            }
        }
    })

    table.insert(nodes, {
        n = G.UIT.R,
        config = { align = "cm", padding = 0.05 },
        nodes = {
            {
                n = G.UIT.T,
                config = {
                    text = "Requires Intiface Central running on default port",
                    colour = G.C.UI.TEXT_INACTIVE,
                    scale = 0.3
                }
            }
        }
    })

    return {
        n = G.UIT.ROOT,
        config = { align = "cm", padding = 0.15, colour = G.C.CLEAR },
        nodes = nodes
    }
end

local function buildAdvancedTab()
    local nodes = {}

    table.insert(nodes, {
        n = G.UIT.R,
        config = { align = "cm", padding = 0.05 },
        nodes = {
            {
                n = G.UIT.T,
                config = {
                    text = "━━━ Trigger Mode ━━━",
                    colour = G.C.UI.TEXT_LIGHT,
                    scale = 0.35
                }
            }
        }
    })

    table.insert(nodes, {
        n = G.UIT.R,
        config = { align = "cm", padding = 0.05 },
        nodes = {
            {
                n = G.UIT.C,
                config = { align = "cm", padding = 0.15 },
                nodes = {
                    create_option_cycle({
                        label = "Blind Exceeded",
                        options = {"Off", "20%", "50%", "100%"},
                        current_option = mod.config.blind_exceeded_mode,
                        ref_table = mod.config,
                        ref_value = "blind_exceeded_mode",
                        opt_callback = "eb_latro_option_cycle_callback"
                    })
                }
            }
        }
    })

    table.insert(nodes, {
        n = G.UIT.R,
        config = { align = "cm", padding = 0.05 },
        nodes = {
            {
                n = G.UIT.T,
                config = {
                    text = "━━━ Blending ━━━",
                    colour = G.C.UI.TEXT_LIGHT,
                    scale = 0.35
                }
            }
        }
    })

    table.insert(nodes, {
        n = G.UIT.R,
        config = { align = "cm", padding = 0.05 },
        nodes = {
            {
                n = G.UIT.C,
                config = { align = "cm", padding = 0.15 },
                nodes = {
                    create_option_cycle({
                        label = "Blend Mode",
                        options = {"Max", "Sum"},
                        current_option = mod.config.blend_mode,
                        ref_table = mod.config,
                        ref_value = "blend_mode",
                        opt_callback = "eb_latro_option_cycle_callback"
                    })
                }
            }
        }
    })

    table.insert(nodes, {
        n = G.UIT.R,
        config = { align = "cm", padding = 0.05 },
        nodes = {
            {
                n = G.UIT.T,
                config = {
                    text = "━━━ Display ━━━",
                    colour = G.C.UI.TEXT_LIGHT,
                    scale = 0.35
                }
            }
        }
    })

    table.insert(nodes, {
        n = G.UIT.R,
        config = { align = "cm", padding = 0.05 },
        nodes = {
            {
                n = G.UIT.C,
                config = { align = "cm", padding = 0.15 },
                nodes = {
                    create_toggle({
                        label = "Show Vibration Level Overlay",
                        ref_table = mod.config,
                        ref_value = "show_overlay"
                    })
                }
            }
        }
    })

    return {
        n = G.UIT.ROOT,
        config = { align = "cm", padding = 0.15, colour = G.C.CLEAR },
        nodes = nodes
    }
end

function mod.extra_tabs()
    return {
        {
            label = "Advanced",
            tab_definition_function = buildAdvancedTab
        }
    }
end

connect_to_intiface()
