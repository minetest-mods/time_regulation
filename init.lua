--------------------
-- Time Regulation
-- By Mg/LeMagnesium
-- License: WTFPL
-- Last modification :
-- 02/17/16 @ 07:33PM GMT+1 (Mg)
--

-- Namespace first, with basic informations
time_reg = {}
time_reg.version = "00.01.15"
time_reg.authors = {"Mg/LeMagnesium"}

-- Definitions
time_reg.enabled = not (minetest.setting_getbool("disable_time_regulation") or false)
time_reg.seasons_mode = minetest.setting_getbool("seasonal_time_regulation") or false
time_reg.offset = 0.2

time_reg.day_of_year = tonumber(os.date("%j"))

time_reg.time_speed = 72

time_reg.loop_interval = 0
time_reg.loop_active = false

time_reg.threshold = {}
time_reg.threshold.day = 5000 -- time units
time_reg.threshold.night = 19000 -- time units

time_reg.moment = ""
time_reg.duration = 1440 / time_reg.time_speed
time_reg.day_time_speed = 0
time_reg.night_time_speed = 0
--[[ Status :
    0: Dead
    1: Idle
    2: Active
]]

time_reg.status = 2

time_reg.ratio = { -- Expressed in percent
        day = tonumber(minetest.setting_get("day_time_ratio")) or 50,
        night = tonumber(minetest.setting_get("night_time_ratio")) or 50,
}
if (time_reg.ratio.day + time_reg.ratio.night ~= 100) or time_reg.ratio.day < 0 or time_reg.ratio.night < 0 then
        minetest.log("error", ("[TimeRegulation] Invalid ratio : %d/100 day & %d/100 night. Setting to 50/50"):format(time_reg.ratio.day, time_reg.ratio.night))
        time_reg.ratio.day, time_reg.ratio.night = 50, 50
end

-- Crappy overrides
local old_settime_func = core.chatcommands["time"].func
core.chatcommands["time"].func = function(...)
        local res, msg = old_settime_func(...)
                if res and time_reg.status == 2 then
                time_reg.do_calculation()
                time_reg.loop(false, true)
                minetest.log("action", "[TimeRegulation] Settime override : updating regulation")
        end
        return res, msg
end

local old_set_func = core.chatcommands["set"].func
core.chatcommands["set"].func = function(...)
        local res, msg = old_set_func(...)
        if res and time_reg.status ~= 0 then
                time_reg.update_constants()
                time_reg.loop(false, true)
                minetest.log("action", "[TimeRegulation] Set override : updating constants and regulation")
        end
        return res, msg
end


-- Then methods
function time_reg.do_calculation()
        time_reg.time_speed = tonumber(minetest.setting_get("time_speed")) -- Absolute Time Speed
        time_reg.duration = 1440 / time_reg.time_speed -- Absolute Human Speed
        local day_htime, night_htime = time_reg.duration * (time_reg.ratio.day/100), time_reg.duration * (time_reg.ratio.night/100)
        time_reg.loop_interval = (math.min(night_htime, day_htime) / 12) * 60
        time_reg.day_time_speed = 1440 / (day_htime * 2)
        time_reg.night_time_speed = 1440 / (night_htime * 2)
end

function time_reg.seasonal_calculation()
        local year = tonumber(os.date("%Y"))
        local nbdays = 365
        if (year % 4) == 0 and not (year % 1000) ~= 0 then
                nbdays = 366
        end
        time_reg.ratio.night = ((math.cos((time_reg.day_of_year / 1) * 2 * math.pi) * time_reg.offset) / 2.0) + 0.5
        time_reg.ratio.day = 100 - time_reg.ratio.night

        minetest.log("action", "[TimeRegulation] Seasonal calculation done")
end

function time_reg.update_constants()
        time_reg.time_speed = minetest.setting_get("time_speed") or time_reg.time_speed
        time_reg.do_calculation()
        if time_reg.status == 1 and time_reg.time_speed > 0 then
                time_reg.set_status(2, "ACTIVE")
        end
end

function time_reg.start_loop()
        if time_reg.loop_active then
                minetest.log("action", "[TimeRegulation] Will not start the loop : one is already running")
                return false
        end
        time_reg.loop_active = true
        minetest.log("action", "[TimeRegulation] Loop started")
        minetest.after(0, time_reg.loop, true)
        return true
end

function time_reg.stop_loop()
        if not time_reg.loop_active then
                minetest.log("action", "[TimeRegulation] Will not break the loop : no loop running")
                return false
        end
        time_reg.loop_active = false
        minetest.log("action", "[TimeRegulation] Loop asked to stop")
        return true
end

function time_reg.set_status(x, title)
        minetest.log("action", "[TimeRegulation] Entered status " .. x .. " (" .. title .. ")")
        time_reg.status = x
end

-- And the loop
function time_reg.loop(loop, forceupdate)
        -- Determine TOD and current moment
        local tod = minetest.get_timeofday() * 24000
        local doy = tonumber(os.date("%j"))

        if time_reg.seasons_mode then
                if doy ~= time_reg.day_of_year then
                        time_reg.seasonal_calculation()
                end
                time_reg.day_of_year = doy
        end

        local moment = "day"
        if tod < time_reg.threshold.day or tod > time_reg.threshold.night then
                moment = "night"
        end

        if time_reg.time_speed == 0 then
                time_reg.set_status(1, "IDLE")
                return
        end

        -- Update if threshold reached
        if moment ~= time_reg.moment or forceupdate then
                -- We've reached a treshold
                time_reg.moment = moment

                if moment == "day" then
                        if time_reg.ratio.day == 0 then
                                minetest.set_timeofday(time_reg.threshold.night / 24000)
                                minetest.log("action", "[TimeRegulation] Entering day period : period skipped")
                        else
                                minetest.setting_set("time_speed", time_reg.day_time_speed)
                                minetest.log("action", "[TimeRegulation] Entering day period : time_speed " .. time_reg.day_time_speed)
                        end
                else
                        if time_reg.ratio.night == 0 then
                                minetest.set_timeofday(time_reg.threshold.day / 24000)
                                minetest.log("action", "[TimeRegulation] Entering night period : period skipped")
                        else
                                minetest.setting_set("time_speed", time_reg.night_time_speed)
                                minetest.log("action", "[TimeRegulation] Entering night period : time_speed " .. time_reg.night_time_speed)
                        end
                end
        end

        -- Loop if we weren't broken
        if loop then
                minetest.after(time_reg.loop_interval, time_reg.loop, time_reg.loop_active)
        else
                minetest.log("action", "[TimeRegulation] Loop stopped")
        end
end

time_reg.update_constants()

if time_reg.enabled then
        time_reg.start_loop()
end

-- chatcommand
minetest.register_chatcommand("time_reg", {
        description = "Control time_regulation",
        privs = {server = true},
        func = function(name, param)
                if param == "" then
                        return true, "see /time_reg help"

                elseif param == "help" then
                        return true, "Supported commands: start, stop, set"

                elseif param == "stop" then
                        local res = time_reg.stop_loop()
                        if res then
                                time_reg.set_status(0, "DEAD")
                                return true, "Loop was told to stop\nTime regulation disabled"
                        else
                                return false, "Loop couldn't be stopped, it isn't running"
                        end

                elseif param == "start" then
                        local res = time_reg.start_loop()
                        if res then
                                time_reg.set_status(2, "ACTIVE")
                                time_reg.update_constants()
                                return true, "Loop started. Time regulation enabled"
                        else
                                return false, "Loop couldn't be started, it already is"
                        end

                elseif param:split(" ")[1] == "set" then
                        local params = param:split(" ")
                        if #params < 3 then
                                return false, "Not enough parameters. You need to enter 'set', a moment of the day ('night' or 'day') and a percentage (0 to 100)"
                        elseif #params > 3 then
                                return false, "You entered too many parameters"
                        end

                        local moment, perc = params[2], tonumber(params[3])
                        if not perc or perc < 0 or perc > 100 then
                                return false, "Invalid percentage : " .. params[3]
                        end

                        if time_reg.seasons_mode then
                                return false, "Season mode is enabled. Turn it off before changing the ratios (see /time_reg help)"
                        end

                        if moment == "day" then
                                time_reg.ratio.day = perc
                                time_reg.ratio.night = 100 - perc

                        elseif moment == "night" then
                                time_reg.ratio.night = perc
                                time_reg.ratio.day = 100 - perc

                        else
                                return false, "Invalid moment of the day : " .. moment .. ". Use either 'day' or 'night'"
                        end

                        time_reg.update_constants()
                        time_reg.loop(false, true)
                        return true, "Operation succeeded.\nRatio: " .. time_reg.ratio.day .. "% day and " .. time_reg.ratio.night .. "% night"

                elseif param:split(" ")[1] == "seasons" then
                        local params = param:split(" ")
                        if #params ~= 2 then
                                return false, "Invalid amount of parameters"
                        end

                        if params[2] == "on" then
                                if time_reg.seasons_mode then
                                        return true, "Seasonal ratio calculation is already on"
                                else
                                        time_reg.seasons_mode = true
                                        return true, "Seasonal ratio calculation is on"
                                end
                        elseif params[2] == "off" then
                                if time_reg.seasons_mode then
                                        time_reg.seasons_mode = false
                                        return true, "Seasonal ratio calculation is off"
                                else
                                        return true, "Seasonal ratio calculation is already off"
                                end
                        else
                                return false, "Unknown state : " .. params[2] .. ". Use either 'on' or 'off'"
                        end

                else
                        return false, "Unknown subcommand: " .. param
                end
        end
})

-- Startup informations
local function log(x) minetest.log("action", "[TimeRegulation] " .. (x or "")) end

log("Thank you for using TimeRegulation v" .. time_reg.version .. " by " .. table.concat(time_reg.authors, ", "))
log("Status: " .. time_reg.status)
log("Absolute Time Speed: " .. time_reg.time_speed)
log("Duration: " .. time_reg.duration)
log("Loop interval: " .. time_reg.loop_interval .. "s")
if time_reg.seasons_mode then
        time_reg.seasonal_calculation()
        log("Seasonal ratio calculation: on")
else
        log("Seasonal ratio calculation: off")
end
log("Ratio:")
log("\tDay: " .. time_reg.ratio.day .. "%")
log("\tNight: " .. time_reg.ratio.night .. "%")
log("Applied time speeds:")
log("\tDay: " .. time_reg.day_time_speed)
log("\tNight: " .. time_reg.night_time_speed)

if not time_reg.enabled then
        log("Time Regulation is disabled by default. Use /time_reg start to start it")
end
