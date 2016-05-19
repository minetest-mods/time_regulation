--------------------
-- Time Regulation
-- By Mg/LeMagnesium
-- License: WTFPL
-- Last modification :
-- 05/18/16 @ 05:20PM GMT+1 (Mg)
--

-- Namespace first, with basic informations
time_reg = {}
time_reg.version = "00.01.26"
time_reg.authors = {"Mg/LeMagnesium"}

-- Definitions
time_reg.enabled = not (minetest.setting_getbool("disable_time_regulation") or false)
time_reg.seasons_mode = minetest.setting_getbool("seasonal_time_regulation") or false
time_reg.real_life_seasons = minetest.setting_getbool("use_real_life_seasons") or false
time_reg.offset = 0.5

if time_reg.real_life_seasons then
	time_reg.day_of_year = tonumber(os.date("%j"))
else
	time_reg.day_of_year = 0 -- Updated at first update_constants
end

time_reg.time_speed = tonumber(minetest.setting_get("time_speed") or "72")

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
    1: Booting
    2: Idle
    3: Active
]]

time_reg.STATUS_DEAD, time_reg.STATUS_BOOTING, time_reg.STATUS_IDLE, time_reg.STATUS_ACTIVE = 0, 1, 2, 3
time_reg.status = time_reg.STATUS_BOOTING

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
   if res and time_reg.status == time_reg.STATUS_ACTIVE then
      time_reg.log("Settime override : updating regulation")
      time_reg.loop(false, true)
   end
   return res, msg
end

local old_set_func = core.chatcommands["set"].func
core.chatcommands["set"].func = function(...)
   local res, msg = old_set_func(...)
   if res and time_reg.status ~= time_reg.STATUS_DEAD and tonumber(minetest.setting_get("time_speed")) ~= time_reg.time_speed then
      time_reg.log("Set override : updating constants and regulation")
      time_reg.update_constants({time_speed = true})
   end
   return res, msg
end


-- Then functions

-- Information functions
-- 	Function meant to be an alias to minetest.log("action", "[TimeRegulation] " + parameters)
function time_reg.log(x) minetest.log("action", "[TimeRegulation] " .. (x or "")) end

-- Standard calculation function
--	Function used when performing calculation of standard method (meaning that we already have the ratio)
function time_reg.std_calculation()
   time_reg.log("Calculation using time_speed = " .. time_reg.time_speed)
   local day_htime, night_htime = time_reg.duration * (time_reg.ratio.day/100), time_reg.duration * (time_reg.ratio.night/100)
   time_reg.day_time_speed = 1440 / day_htime / 2 -- Human times are divided per two since we only span half a cycle for each period of a day
   time_reg.night_time_speed = 1440 / night_htime / 2
   time_reg.log("Output is : " .. time_reg.day_time_speed .. " (day); " .. time_reg.night_time_speed .. " (night)")
end

-- Seasonal calculation function
--	It contains the formula to calculate day/night ratio depending on in game/real life day of a year
function time_reg.seasonal_calculation()
        local ylength = 365
        local year = math.floor(time_reg.day_of_year / ylength)
	if time_reg.real_time_seasons and (year % 4 == 0) and ((year % 400 ~= 0 and year % 600 == 0) or (year % 600 ~= 0 and year % 400 == 0)) then
	   ylength = 366
	end

	time_reg.ratio.night = (((math.cos((time_reg.day_of_year / ylength) * 2 * math.pi) * time_reg.offset) / 2.0) + 0.5) * 100
	time_reg.ratio.day = 100 - time_reg.ratio.night

        time_reg.log("Seasonal calculation done")
end

-- Constants update function
--	Global constant update used to update calculation values
--	It needs a parameter, a table with key/value elements. The following keys are available :
--		- time_speed : true to update time_speed
--		- date : true to update the current date from either the game or real life
function time_reg.update_constants(tab)
   if tab.time_speed then
      -- Updating time_speed should only be done when booting, or after an update of time_speed's value in MT's configuration
      time_reg.time_speed = tonumber(minetest.setting_get("time_speed")) or time_reg.time_speed -- Absolute Time Speed
      time_reg.duration = 1440 / time_reg.time_speed -- Absolute Human Speed

      if time_reg.status == time_reg.STATUS_IDLE and time_reg.time_speed > 0 then
	 time_reg.start_loop()
      elseif time_reg.status == time_reg.STATUS_ACTIVE and time_reg.time_speed == 0 then
	 time_reg.stop_loop()
      else
	 time_reg.loop(false)
      end
   end

   if tab.date then
      if time_reg.real_life_seasons then
	 time_reg.day_of_year = tonumber(os.date("%j"))
      else
	 time_reg.day_of_year = minetest.get_day_count()
      end
      -- Since we (hypothetically) changed the current day we compute again our seasonal rations
      if time_reg.seasons_mode then
	 time_reg.seasonal_calculation() -- Calculate season-dependant ratio
      end
   end
end

-- Central computing function
--	A computing function separated from update_constants, for clarity's sake
function time_reg.compute()
   if time_reg.status == time_reg.STATUS_ACTIVE then
      time_reg.std_calculation() -- Use ratio and time_speed to calculate time
      time_reg.loop_interval = math.min(1440 / time_reg.night_time_speed / 2, 1440 / time_reg.night_time_speed / 2) * 30 -- (not 60, we only want half of it)
   end
end	

-- Start the Loop
--	Launch the Loop with the order to repeat itself indefinitely
function time_reg.start_loop()
        if time_reg.loop_active then
                time_reg.log("Will not start the loop : one is already running")
                return false
        end
        time_reg.loop_active = true
	if time_reg.status ~= time_reg.STATUS_ACTIVE then
		time_reg.set_status(time_reg.STATUS_ACTIVE, "ACTIVE")
	end
	time_reg.loop(true)
        time_reg.log("Loop started")
	return true
end

-- Stop the Loop
--	Break the Loop by setting time_reg.loop_active to false, unless it isn't running
function time_reg.stop_loop()
        if not time_reg.loop_active then
                time_reg.log("Will not break the loop : no loop running")
                return false
        end
        time_reg.loop_active = false
        time_reg.log("Loop asked to stop")
        return true
end

-- Set status
--	Set the mechanism's current status (an integer, and a title)
function time_reg.set_status(x, title)
        time_reg.log("Entered status " .. x .. " (" .. title .. ")")
        time_reg.status = x
end

-- And the loop
function time_reg.loop(loop, forceupdate)
	if not loop then
	   time_reg.log("Loop running as standalone")
	end

   	-- Do all calculations
	time_reg.update_constants({date = true})
	time_reg.compute()
	if not time_reg.loop_active then
	   time_reg.set_status(time_reg.STATUS_IDLE, "IDLE")
	   time_reg.log("Loop broken")
	   return
	end

        local tod = minetest.get_timeofday() * 24000

        local moment = "day"
        if tod < time_reg.threshold.day or tod > time_reg.threshold.night then
                moment = "night"
        end

        -- Update if threshold reached
        if moment ~= time_reg.moment or forceupdate then
                -- We've reached a treshold
                time_reg.moment = moment

                if moment == "day" then
                        if time_reg.ratio.day == 0 then
                                minetest.set_timeofday(time_reg.threshold.night / 24000)
                                time_reg.log("Entering day period : period skipped")
                        else
                                minetest.setting_set("time_speed", time_reg.day_time_speed)
                                time_reg.log("Entering day period : time_speed " .. time_reg.day_time_speed)
                        end
                else
                        if time_reg.ratio.night == 0 then
                                minetest.set_timeofday(time_reg.threshold.day / 24000)
                                time_reg.log("Entering night period : period skipped")
                        else
                                minetest.setting_set("time_speed", time_reg.night_time_speed)
                                time_reg.log("Entering night period : time_speed " .. time_reg.night_time_speed)
                        end
                end
        end

        -- Loop if we weren't broken
        if loop then
                minetest.after(time_reg.loop_interval, time_reg.loop, time_reg.loop_active)
        else
                time_reg.log("Loop stopped")
        end
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
                                time_reg.set_status(time_reg.STATUS_DEAD, "DEAD")
                                return true, "Loop was told to stop\nTime regulation disabled"
                        else
                                return false, "Loop couldn't be stopped, it isn't running"
                        end

                elseif param == "start" then
                        local res = time_reg.start_loop()
                        if res then
                                time_reg.set_status(time_reg.STATUS_ACTIVE, "ACTIVE")
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

                        time_reg.compute()
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

--		elseif param:split(" ")[1] == -- For real time use toggling; NIY

                else
                        return false, "Unknown subcommand: " .. param
                end
        end
})

-- Init
--	Set all variables and activate all mechanisms
function time_reg.init()
   time_reg.set_status(time_reg.STATUS_ACTIVE, "ACTIVE")
   time_reg.log("Starting time regulation mechanisms...")

   if time_reg.seasons_mode then
      time_reg.log("Seasonal ratio calculation: on")
      if time_reg.real_life_seasons then
	 time_reg.log("Seasonal ratio calculated from real life date")
      else
	 time_reg.log("Seasonal ratio calculated from game date")
      end
   else
      time_reg.log("Seasonal ratio calculation: off")
   end

   if not time_reg.enabled then
      time_reg.log("Time Regulation is disabled by default. Use /time_reg start to start it")
   else
      time_reg.start_loop()
   end

   time_reg.log("Duration: " .. time_reg.duration .. " minutes")
   time_reg.log("Loop interval: " .. time_reg.loop_interval .. "s")
   time_reg.log("Ratio:")
   time_reg.log("\tDay: " .. time_reg.ratio.day .. "%")
   time_reg.log("\tNight: " .. time_reg.ratio.night .. "%")
   time_reg.log("Applied time speeds:")
   time_reg.log("\tDay: " .. time_reg.day_time_speed)
   time_reg.log("\tNight: " .. time_reg.night_time_speed)
   time_reg.log("Human Durations of Half-Cycles:")
   time_reg.log("\tDay: " .. 1440 / time_reg.day_time_speed / 2 .. " minutes")
   time_reg.log("\tNight: " .. 1440 / time_reg.night_time_speed / 2 .. " minutes")
end

-- Shutdown
-- 	Sometimes MT will shutdown and write current time_speed in minetest.conf; we need to change the value back to normal before it happens
function time_reg.on_shutdown()
	minetest.setting_set("time_speed", time_reg.time_speed)
	time_reg.log("Time speed set back to " .. time_reg.time_speed)
end

minetest.register_on_shutdown(time_reg.on_shutdown)

-- --[[ NOW WE SHALL START ]]-- --

time_reg.log("Thank you for using TimeRegulation v" .. time_reg.version .. " by " .. table.concat(time_reg.authors, ", "))
time_reg.log("Status: " .. time_reg.status)
time_reg.log("Absolute Time Speed: " .. time_reg.time_speed)

minetest.after(0.1, time_reg.init)

