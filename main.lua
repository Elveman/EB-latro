local mod = SMODS.current_mod

local buttplug = nil
local isConnected = false
local isConnecting = false
local initFailed = false
local initError = nil

local vibrationEndTime = 0
local vibrationIntensity = 0
local lastSendTime = 0
local MIN_SEND_INTERVAL = 0.08
local MIN_HOLD_AFTER_BUMP = 1.5
local MAX_SCORING_DURATION = 30.0
local scoringActive = false
local scoringStartTime = 0

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

function bumpVibration(amount)
    if not (isConnected and not initFailed and buttplug) then return end
    if not scoringActive then return end
    vibrationIntensity = math.min(1, vibrationIntensity + amount)
    local now = G.TIMERS and G.TIMERS.REAL or 0
    vibrationEndTime = math.max(vibrationEndTime, now + MIN_HOLD_AFTER_BUMP)
    if now - lastSendTime >= MIN_SEND_INTERVAL then
        sendRaw(vibrationIntensity)
        lastSendTime = now
    end
end

function stopVibration()
    vibrationIntensity = 0
    vibrationEndTime = 0
    lastSendTime = 0
    sendRaw(0)
end

-- Global play_sound wrapper: drives vibration from scoring audio events
if not _buttplug_original_play_sound then
    _buttplug_original_play_sound = play_sound

    play_sound = function(sound, pitch, volume)
        if G.STATE == G.STATES.HAND_PLAYED then
            -- chips2 with pitch=0 fires both at scoring start AND end
            if sound == 'chips2' and (not pitch or pitch == 0) then
                if not scoringActive then
                    -- START of scoring phase
                    scoringActive = true
                    scoringStartTime = G.TIMERS and G.TIMERS.REAL or 0
                    vibrationIntensity = 0
                    vibrationEndTime = 0
                    lastSendTime = 0
                    sendRaw(mod.config.start_intensity / 100)
                else
                    -- END of scoring phase
                    scoringActive = false
                    stopVibration()
                end
            -- Scoring trigger sounds: cards, jokers, bonuses, gold seals
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
    ok, bp = pcall(require, "buttlatro_buttplug")
    if not ok then
        initFailed = true
        initError = tostring(bp)
        sendErrorMessage("Failed to load buttplug module: " .. initError, "Buttlatro")
        return
    end
    buttplug = bp

    table.insert(buttplug.cb.ServerInfo, function()
        isConnected = true
        isConnecting = false
        sendInfoMessage("Connected to Intiface server", "Buttlatro")
        buttplug.request_device_list()
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
        buttplug.connect("Buttlatro", server_addr)
    end)

    if conn_ok then
        isConnecting = true
    else
        initFailed = true
        initError = tostring(conn_err)
        sendErrorMessage("Failed to connect: " .. initError, "Buttlatro")
    end
end

function pollButtplugMessages()
    if buttplug and (isConnecting or isConnected) then
        local now = G.TIMERS and G.TIMERS.REAL or 0

        -- Safety: force-end scoring if it has been active too long
        if scoringActive and now - scoringStartTime > MAX_SCORING_DURATION then
            scoringActive = false
            stopVibration()
        end

        -- Auto-stop vibration when timer expires AND not in active scoring
        if isConnected and vibrationEndTime > 0 and now >= vibrationEndTime and not scoringActive then
            vibrationEndTime = 0
            vibrationIntensity = 0
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
                        sendErrorMessage("Buttlatro: " .. initError, "Buttlatro")
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
                    sendErrorMessage("Buttlatro: " .. initError, "Buttlatro")
                end
                isConnecting = false
                isConnected = false
                break
            end
        end
    end
end

function G.FUNCS.buttlatro_start_test()
    sendRaw(0.5)
    vibrationIntensity = 0.5
    vibrationEndTime = -1
end

function G.FUNCS.buttlatro_stop_test()
    sendRaw(0)
    vibrationIntensity = 0
    vibrationEndTime = 0
end

mod.config_tab = function()
    local nodes = {}

    if initFailed then
        table.insert(nodes, {
            n = G.UIT.R,
            config = { align = "cm", padding = 0.1 },
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
            config = { align = "cm", padding = 0.1 },
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
            config = { align = "cm", padding = 0.1 },
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
            config = { align = "cm", padding = 0.1 },
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
        config = { align = "cm", padding = 0.15 },
        nodes = {
            {
                n = G.UIT.C,
                config = { align = "cm", padding = 0.3 },
                nodes = {
                    create_slider({
                        label = "Start Intensity (%)", w = 4, h = 0.4,
                        ref_table = mod.config, ref_value = "start_intensity",
                        min = 0, max = 10, decimal_places = 0
                    })
                }
            },
            {
                n = G.UIT.C,
                config = { align = "cm", padding = 0.3 },
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
        config = { align = "cm", padding = 0.2 },
        nodes = {
            {
                n = G.UIT.C,
                config = { align = "cm", padding = 0.1 },
                nodes = {
                    {
                        n = G.UIT.C,
                        config = {
                            align = "cm",
                            padding = 0.15,
                            minh = 0.6,
                            r = 0.1,
                            hover = true,
                            colour = G.C.GREEN,
                            button = "buttlatro_start_test",
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
                config = { align = "cm", padding = 0.1 },
                nodes = {
                    {
                        n = G.UIT.C,
                        config = {
                            align = "cm",
                            padding = 0.15,
                            minh = 0.6,
                            r = 0.1,
                            hover = true,
                            colour = G.C.RED,
                            button = "buttlatro_stop_test",
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
        config = { align = "cm", padding = 0.1 },
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
        config = { align = "cm", padding = 0.2, colour = G.C.CLEAR },
        nodes = nodes
    }
end

connect_to_intiface()
